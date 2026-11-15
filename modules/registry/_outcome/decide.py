"""Bound decision prompts and answers; no adapter is enabled by default."""

import argparse
import json
import os
from pathlib import Path
import re
import sys

from outcome import load_valid, parse_json, read_json, rfc3339, validate


DECISION_KEYS = {"schema", "decisionId", "assignment", "question", "options", "recommendation", "scope"}
ANSWER_KEYS = {"schema", "decisionId", "option", "scope", "promote", "note"}


def validate_decision(value):
    if not isinstance(value, dict) or set(value) != DECISION_KEYS:
        raise ValueError("decision must contain exactly the agentic.decision/1 fields")
    if value["schema"] != "agentic.decision/1":
        raise ValueError("unsupported decision schema")
    # Reuse the outcome contract, including assignment, option uniqueness and
    # recommendation membership, instead of maintaining a second validator.
    body = {key: value[key] for key in ("question", "options", "recommendation", "scope")}
    body.update(id=value["decisionId"], context="Checkpoint decision.")
    errors = validate({"schema": "agentic.outcome/1", "kind": "blocked:decision",
                       "assignment": value["assignment"], "summary": "", "decision": body})
    if errors:
        raise ValueError(errors[0])
    return value


def from_outcome(value):
    if value["kind"] != "blocked:decision":
        raise ValueError("expected a blocked:decision outcome")
    body = value["decision"]
    return validate_decision({"schema": "agentic.decision/1", "decisionId": body["id"],
                              "assignment": value["assignment"], **{key: body[key] for key in
                              ("question", "options", "recommendation", "scope")}})


def plain(text):
    return " ".join(text.split())


def display(text):
    # Even a question consisting solely of a fence marker stays plain prose.
    return plain(text).replace("`", "\\`")


def prompt(value):
    validate_decision(value)
    lines = [display(value["question"])]
    lines += [f"{display(o['id'])}: {display(o['label'])} — {display(o['consequences'])}" for o in value["options"]]
    lines += ["Recommendation: " + display(value["recommendation"]),
              "```agentic-decision", json.dumps(value, ensure_ascii=True), "```"]
    return "\n".join(lines) + "\n"


def parse_prompt(text):
    blocks = re.findall(r"^```agentic-decision[ \t]*\r?\n(.*?)^```[ \t]*\r?$", text, re.MULTILINE | re.DOTALL)
    openings = re.findall(r"^```agentic-decision[ \t]*\r?$", text, re.MULTILINE)
    if len(blocks) != 1 or len(openings) != 1:
        raise ValueError("expected exactly one fenced agentic-decision block")
    return validate_decision(parse_json(blocks[0]))


def check_answer(decision, value):
    validate_decision(decision)
    required = ANSWER_KEYS - {"note"}
    if not isinstance(value, dict) or not required <= set(value) <= ANSWER_KEYS:
        raise ValueError("answer has missing or unexpected fields")
    if value["schema"] != "agentic.decision-answer/1":
        raise ValueError("unsupported answer schema")
    if value["decisionId"] != decision["decisionId"]:
        raise ValueError("decision id mismatch")
    if value["option"] not in [o["id"] for o in decision["options"]]:
        raise ValueError("unknown option")
    if value["scope"] != decision["scope"]:
        raise ValueError("scope mismatch")
    if type(value["promote"]) is not bool:
        raise ValueError("promote must be boolean")
    if "note" in value and not isinstance(value["note"], str):
        raise ValueError("note must be a string")


def nix_string(value):
    # Escape Nix interpolation as well as string delimiters. Keep Unicode
    # literal: JSON's \\u (and \\b/\\f) escapes are not Nix escapes.
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("${", r"\${")
    for char, replacement in (("\n", r"\n"), ("\r", r"\r"), ("\t", r"\t")):
        escaped = escaped.replace(char, replacement)
    return '"' + escaped + '"'


def promote(decision, answer, granted_by, granted_at):
    check_answer(decision, answer)
    if not answer["promote"]:
        raise ValueError("promotion requires promote: true in the answer")
    if not re.fullmatch(r"[a-z0-9-]+", decision["decisionId"]):
        raise ValueError("standing rule id must be a [a-z0-9-] token")
    if not granted_by.strip():
        raise ValueError("granted-by must name the grantor")
    if not rfc3339(granted_at):
        raise ValueError("granted-at must be an RFC 3339 date-time with timezone")
    option = next(o for o in decision["options"] if o["id"] == answer["option"])
    rule = f"{plain(option['label'])} — {plain(option['consequences'])} Scope: {plain(decision['scope'])}"
    source = "decision:" + decision["decisionId"]
    if "issue" in decision["assignment"]:
        source += " " + decision["assignment"]["issue"]
    entry = {"id": decision["decisionId"], "rule": rule, "source": source,
             "grantedBy": granted_by, "grantedAt": granted_at}
    return "{\n" + "".join(f"  {key} = {nix_string(value)};\n" for key, value in entry.items()) + "}\n"


def adapter():
    name = os.environ.get("WORKBENCH_DECIDE_ADAPTER")
    if name == "cotal":
        from decide_cotal import CotalAdapter
        return CotalAdapter()
    if name == "fake" or (name is None and os.environ.get("WORKBENCH_DECIDE_FAKE")):
        from decide_fake import FakeAdapter
        return FakeAdapter()
    raise ValueError("no adapter enabled; set WORKBENCH_DECIDE_FAKE or explicitly opt in with WORKBENCH_DECIDE_ADAPTER=cotal (UNVERIFIED)")


def open_decisions(source):
    rows = source.open_decisions()
    if not isinstance(rows, list):
        raise ValueError("adapter returned an invalid decision list")
    seen_ids, seen_steps = set(), set()
    for row in rows:
        if not isinstance(row, dict) or set(row) != {"run", "stepKey", "decision"}:
            raise ValueError("adapter returned an invalid decision row")
        for key in ("run", "stepKey"):
            if not isinstance(row[key], str) or not row[key] or row[key].startswith("-"):
                raise ValueError("adapter returned an invalid run or step key")
        decision = validate_decision(row["decision"])
        bound_run = decision["assignment"].get("run")
        if bound_run is not None and bound_run != row["run"]:
            raise ValueError("assignment run mismatch")
        identifier = (row["run"], decision["decisionId"])
        step = (row["run"], row["stepKey"])
        if identifier in seen_ids or step in seen_steps:
            raise ValueError("adapter returned an ambiguous decision")
        seen_ids.add(identifier)
        seen_steps.add(step)
    return rows


def queue_row(row):
    d = row["decision"]
    return {"run": row["run"], "stepKey": row["stepKey"], "decisionId": d["decisionId"],
            "repo": d["assignment"]["repo"], "issue": d["assignment"].get("issue"),
            **{key: d[key] for key in ("question", "options", "recommendation", "scope")}}


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def main():
    parser = Parser(description=__doc__, allow_abbrev=False)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("prompt", "parse", "check-answer", "promote"):
        sub = commands.add_parser(name, allow_abbrev=False)
        sub.add_argument("file")
        if name in ("check-answer", "promote"):
            sub.add_argument("answer")
        if name == "promote":
            sub.add_argument("--granted-by", required=True)
            sub.add_argument("--granted-at", required=True)
    commands.add_parser("queue", allow_abbrev=False).add_argument("--json", action="store_true")
    sub = commands.add_parser("answer", allow_abbrev=False)
    for flag in ("run", "decision", "option"):
        sub.add_argument("--" + flag, required=True)
    sub.add_argument("--promote", action="store_true")
    sub.add_argument("--note")
    try:
        args = parser.parse_args()
        if args.command == "prompt":
            print(prompt(from_outcome(load_valid(args.file))), end="")
        elif args.command in ("parse", "check-answer", "promote"):
            decision = parse_prompt(Path(args.file).read_text())
            if args.command == "parse":
                print(json.dumps(decision))
            elif args.command == "promote":
                print(promote(decision, read_json(args.answer), args.granted_by, args.granted_at), end="")
            else:
                check_answer(decision, read_json(args.answer))
        else:
            source = adapter()
            rows = open_decisions(source)
            if args.command == "queue":
                values = [queue_row(row) for row in rows]
                if args.json:
                    print(json.dumps(values))
                else:
                    for row in values:
                        print(f"{plain(row['run'])} {plain(row['stepKey'])} {plain(row['decisionId'])} "
                              f"[{plain(row['repo'])} {plain(row['issue'] or '')}] {plain(row['question'])}")
            else:
                matches = [r for r in rows if r["run"] == args.run and r["decision"]["decisionId"] == args.decision]
                if len(matches) != 1:
                    raise ValueError("no unique open decision for run and decision id (unknown or settled)")
                row = matches[0]
                value = {"schema": "agentic.decision-answer/1", "decisionId": args.decision,
                         "option": args.option, "scope": row["decision"]["scope"], "promote": args.promote}
                if args.note is not None:
                    value["note"] = args.note
                check_answer(row["decision"], value)
                source.answer(args.run, row["stepKey"], value)
        return 0
    except (OSError, ValueError) as exc:
        print("workbench-decide: " + plain(str(exc)), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
