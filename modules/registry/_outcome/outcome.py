"""Typed assignment outcomes and read-only evidence probes (Python stdlib only)."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


SCHEMA_PATH = Path(os.environ.get("AGENTIC_OUTCOME_SCHEMA") or (
    Path(__file__).resolve().parents[3] / "schemas/agentic.outcome-1.json"
))
ASK_SCHEMA = {"schema": "string", "kind": "string", "assignment": "record", "summary": "string"}
BODIES = {
    "result": "result", "blocked:decision": "decision", "blocked:approval": "approval",
    "blocked:environment": "environment", "blocked:external": "external",
    "failed": "failed", "handoff": "handoff",
}


def pointer(path, key):
    return path + "/" + str(key).replace("~", "~0").replace("/", "~1")


def validate(value):
    """Hand-written validator for the keywords used by the shipped schema.

    Discriminated oneOf branches are selected before recursion so missing fields
    are reported at their actual JSON pointers, not as an opaque oneOf error.
    """
    schema = json.loads(SCHEMA_PATH.read_text())
    errors = []

    def error(path, reason):
        errors.append(f"{path or '/'}: {reason}")

    def walk(v, rule, path):
        if "$ref" in rule:
            target = schema
            for part in rule["$ref"].split("/")[1:]:
                target = target[part]
            walk(v, target, path)
            return
        if "oneOf" in rule:
            discriminator = rule["x-discriminator"]
            selected = [r for r in rule["oneOf"] if isinstance(v, dict)
                        and v.get(discriminator) == r["properties"][discriminator]["const"]]
            if not selected:
                error(pointer(path, discriminator), "missing or unsupported discriminator")
            else:
                walk(v, selected[0], path)
            return
        kind = rule.get("type")
        valid_type = {
            "object": isinstance(v, dict), "array": isinstance(v, list),
            "string": isinstance(v, str), "integer": type(v) is int or (type(v) is float and v.is_integer()),
            "boolean": type(v) is bool,
        }
        if kind and not valid_type[kind]:
            error(path, f"expected {kind}")
            return
        if "const" in rule and v != rule["const"]:
            error(path, f"must equal {rule['const']!r}")
        if kind == "object":
            for key in rule.get("required", []):
                if key not in v:
                    error(pointer(path, key), "required field missing")
            for key, item in v.items():
                if key in rule.get("properties", {}):
                    walk(item, rule["properties"][key], pointer(path, key))
                elif rule.get("additionalProperties") is False:
                    error(pointer(path, key), "unexpected field")
        elif kind == "array":
            if len(v) < rule.get("minItems", 0):
                error(path, f"requires at least {rule['minItems']} items")
            for index, item in enumerate(v):
                walk(item, rule["items"], pointer(path, index))
        elif kind == "string":
            if len(v) < rule.get("minLength", 0):
                error(path, "must not be empty")
            if len(v) > rule.get("maxLength", sys.maxsize):
                error(path, f"exceeds {rule['maxLength']} characters")
            if "pattern" in rule and re.search(rule["pattern"], v) is None:
                error(path, "does not match required pattern")
            if rule.get("format") == "date-time" and not rfc3339(v):
                error(path, "expected RFC 3339 date-time with timezone")

    walk(value, schema, "")
    # JSON Schema cannot express comparisons between sibling values. These two
    # semantic constraints are declared in the schema's $comment as well.
    if isinstance(value, dict) and value.get("kind") == "blocked:decision":
        decision = value.get("decision")
        if isinstance(decision, dict) and isinstance(decision.get("options"), list):
            ids = [o.get("id") for o in decision["options"] if isinstance(o, dict)
                   and isinstance(o.get("id"), str)]
            if len(ids) != len(set(ids)):
                error("/decision/options", "option ids must be unique")
            if "recommendation" in decision and decision["recommendation"] not in ids:
                error("/decision/recommendation", "must name an option id")
    return errors


def rfc3339(value):
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}[Tt](?:[01]\d|2[0-3]):[0-5]\d:(?:[0-5]\d|60)(?:\.\d+)?(?:[Zz]|[+-](?:[01]\d|2[0-3]):[0-5]\d)", value):
        return False
    try:
        # Python cannot parse the RFC's leap second; validate it as second 59.
        normalized = value.upper()
        normalized = normalized[:17] + normalized[17:19].replace("60", "59") + normalized[19:]
        datetime.datetime.fromisoformat(normalized.replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


def parse_json(text):
    def invalid_constant(value):
        raise ValueError(f"invalid JSON constant {value}")
    return json.loads(text, parse_constant=invalid_constant)


def read_json(filename):
    text = sys.stdin.read() if filename == "-" else Path(filename).read_text()
    return parse_json(text)


def load_valid(filename):
    value = read_json(filename)
    errors = validate(value)
    if errors:
        raise ValueError("\n".join(errors))
    return value


def yield_record(value):
    record = _yield_record(value)
    note = (record["note"].splitlines() or [""])[0]
    record["note"] = note if len(note) <= 200 else note[:199] + "…"
    return record


def _yield_record(value):
    kind = value["kind"]
    body = value[BODIES[kind]]
    if kind == "result":
        return {"status": "done", "note": value["summary"]}
    if kind == "handoff":
        return {"status": "handoff", "to": body["to"], "note": body["reason"]}
    if kind == "failed":
        return {"status": "blocked", "note": "failed: " + body["error"].splitlines()[0]}
    identifier = body.get("id", body.get("code", body.get("waitingOn")))
    return {"status": "blocked", "note": f"{kind} {identifier}"}


def run_command(args):
    return subprocess.run(args, text=True, capture_output=True, timeout=120, check=False)


def probe(item, rerun_checks):
    kind = item["type"]
    if kind in ("ci", "flux"):
        return "unknown", None, "probe not configured (deferred)"
    if kind == "check" and not rerun_checks:
        return "unknown", None, "not re-run"
    try:
        if kind == "file":
            digest = hashlib.sha256()
            with Path(item["path"]).open("rb") as source:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(block)
            observed = digest.hexdigest()
            return ("ok" if observed == item["sha256"] else "mismatch", observed, "sha256 compared")
        if kind == "git-ref":
            result = run_command(["git", "ls-remote", "--", item["remote"], item["ref"]])
            if result.returncode:
                return "unknown", None, "git ls-remote failed"
            refs = [line.split() for line in result.stdout.splitlines()]
            observed = [sha for sha, ref in refs if ref == item["ref"]]
            return ("ok" if observed == [item["sha"]] else "mismatch", observed, "exact ref compared")
        system = run_command(["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"])
        if system.returncode or not re.fullmatch(r"[a-zA-Z0-9_-]+", system.stdout):
            return "unknown", None, "cannot determine current Nix system"
        target = f"{item.get('flake', '.')}#checks.{system.stdout}.{item['attr']}"
        result = run_command(["nix", "build", "--no-link", "--", target])
        observed = result.returncode
        return ("ok" if observed == item["exitCode"] else "mismatch", observed, "check exit code compared")
    except FileNotFoundError as exc:
        detail = "nix not on PATH" if kind == "check" else f"probe unavailable: {type(exc).__name__}"
        return "unknown", None, detail
    except (OSError, subprocess.TimeoutExpired, ValueError) as exc:
        return "unknown", None, f"probe unavailable: {type(exc).__name__}"


def evidence(value):
    if value["kind"] == "result":
        return value["result"]["evidence"]
    if value["kind"] == "blocked:external" and "evidence" in value["external"]:
        return [value["external"]["evidence"]]
    return []


def outcome_main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("ask-schema")
    for name in ("validate", "extract", "yield"):
        sub = commands.add_parser(name)
        sub.add_argument("file", nargs="?" if name == "validate" else None, default="-")
    args = parser.parse_args()
    try:
        if args.command == "ask-schema":
            print(json.dumps(ASK_SCHEMA))
        elif args.command == "extract":
            message = Path(args.file).read_text()
            blocks = re.findall(r"^```agentic-outcome[ \t]*\r?\n(.*?)^```[ \t]*\r?$", message, re.MULTILINE | re.DOTALL)
            if len(blocks) != 1:
                raise ValueError(f"/: expected exactly one agentic-outcome block; found {len(blocks)}")
            value = parse_json(blocks[0])
            if not isinstance(value, dict):
                raise ValueError("/: outcome block must contain a JSON object")
            print(json.dumps(value))
        else:
            value = load_valid(args.file)
            if args.command == "yield":
                print(json.dumps(yield_record(value)))
        return 0
    except (OSError, ValueError) as exc:
        print(str(exc) if str(exc).startswith("/") else f"/: {exc}", file=sys.stderr)
        return 1


def verify_main():
    parser = argparse.ArgumentParser(description="Re-measure outcome evidence. Checks require explicit opt-in.")
    parser.add_argument("file")
    parser.add_argument("--rerun-checks", action="store_true")
    args = parser.parse_args()
    try:
        value = load_valid(args.file)
    except (OSError, ValueError) as exc:
        print(str(exc) if str(exc).startswith("/") else f"/: {exc}", file=sys.stderr)
        return 1
    items = []
    for index, item in enumerate(evidence(value)):
        verdict, observed, detail = probe(item, args.rerun_checks)
        items.append(dict(index=index, type=item["type"], verdict=verdict, observed=observed, detail=detail))
    print(json.dumps({"items": items}))
    return 1 if any(i["verdict"] == "mismatch" for i in items) else 2 if any(i["verdict"] == "unknown" for i in items) else 0


if __name__ == "__main__":
    sys.exit(verify_main() if sys.argv.pop(1) == "verify" else outcome_main())
