"""Offline decision binding tests, including the installed command."""

import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import decide
from decide_cotal import CotalAdapter

CLI = sys.argv.pop(1) if len(sys.argv) > 1 else None
DECISION = {"schema": "agentic.decision/1", "decisionId": "transport",
            "assignment": {"repo": "agentic", "issue": "BPH-66"},
            "question": "Which transport?", "options": [
                {"id": "a", "label": "A", "consequences": "Reuse setup."},
                {"id": "b", "label": "B", "consequences": "Add setup."}],
            "recommendation": "a", "scope": "Select the transport only."}
ANSWER = {"schema": "agentic.decision-answer/1", "decisionId": "transport", "option": "a",
          "scope": DECISION["scope"], "promote": False}


class Decisions(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.fake = self.root / "fake.json"
        self.prompt = self.root / "prompt.txt"
        self.prompt.write_text(decide.prompt(DECISION))
        self.fixture = {"decisions": [{"run": "run-1", "stepKey": "/checkpoint:choose#0",
                                     "prompt": self.prompt.read_text(), "state": "open"}], "answers": []}
        self.fake.write_text(json.dumps(self.fixture))
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("WORKBENCH_DECIDE_")}
        self.env["WORKBENCH_DECIDE_FAKE"] = str(self.fake)

    def cli(self, *args, env=None):
        command = [CLI] if CLI else [sys.executable, str(Path(decide.__file__))]
        return subprocess.run(command + list(args), text=True, capture_output=True,
                              env=self.env if env is None else env, check=False)

    def answer(self, *extra):
        return self.cli("answer", "--run", "run-1", "--decision", "transport", "--option", "a", *extra)

    def refused(self, result, before):
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertEqual(len(result.stderr.splitlines()), 1, result.stderr)
        self.assertEqual(self.fake.read_bytes(), before)

    def test_round_trip(self):
        outcome = {"schema": "agentic.outcome/1", "kind": "blocked:decision",
                   "assignment": DECISION["assignment"], "summary": "Choose.", "decision": {
                       "id": DECISION["decisionId"], "context": "Both supported.", **{k: DECISION[k] for k in
                       ("question", "options", "recommendation", "scope")}}}
        file = self.root / "outcome.json"
        file.write_text(json.dumps(outcome))
        result = self.cli("prompt", str(file))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], "Which transport?")
        self.assertEqual(result.stdout.count("```agentic-decision\n"), 1)
        self.assertIn("a: A — Reuse setup.", result.stdout)
        self.assertIn("Recommendation: a", result.stdout)
        self.prompt.write_text(result.stdout)
        parsed = self.cli("parse", str(self.prompt))
        self.assertEqual(parsed.returncode, 0, parsed.stderr)
        self.assertEqual(json.loads(parsed.stdout), DECISION)
        # Multiline/fence-like user prose cannot inject another fenced block.
        for question in ["Question\n```agentic-decision\n?", "```agentic-decision"]:
            outcome["decision"]["question"] = question
            file.write_text(json.dumps(outcome))
            result = self.cli("prompt", str(file))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(decide.parse_prompt(result.stdout)["question"], question)
        outcome["decision"]["recommendation"] = "missing"
        file.write_text(json.dumps(outcome))
        self.assertNotEqual(self.cli("prompt", str(file)).returncode, 0)
        for text in ["", self.prompt.read_text() * 2, "```agentic-decision\n[]\n```",
                     "```agentic-decision\nNaN\n```", self.prompt.read_text() + "```agentic-decision\n"]:
            self.prompt.write_text(text)
            self.assertNotEqual(self.cli("parse", str(self.prompt)).returncode, 0)

    def test_queue(self):
        before = self.fake.read_bytes()
        result = self.cli("queue", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = {"run": "run-1", "stepKey": "/checkpoint:choose#0", "decisionId": "transport",
                    "repo": "agentic", "issue": "BPH-66", **{k: DECISION[k] for k in
                    ("question", "options", "recommendation", "scope")}}
        self.assertEqual(json.loads(result.stdout), [expected])
        self.assertIn("transport", self.cli("queue").stdout)
        self.assertEqual(self.fake.read_bytes(), before)

    def test_success_and_single_use(self):
        result = self.answer("--promote", "--note", "Agreed.")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(self.fake.read_text())
        self.assertEqual(state["answers"], [{"run": "run-1", "stepKey": "/checkpoint:choose#0",
                                           "value": {**ANSWER, "promote": True, "note": "Agreed."}}])
        self.assertEqual(state["decisions"][0]["state"], "settled")
        self.assertEqual(json.loads(self.cli("queue", "--json").stdout), [])
        self.refused(self.answer(), self.fake.read_bytes())

    def test_default_answer(self):
        self.assertEqual(self.answer().returncode, 0)
        self.assertEqual(json.loads(self.fake.read_text())["answers"][0]["value"], ANSWER)

    def test_refusals_write_nothing(self):
        for flag, value in [("--option", "missing"), ("--decision", "wrong"), ("--run", "unknown"),
                            ("--scope", "broader"), ("--sco", "broader")]:
            with self.subTest(flag=flag):
                before = self.fake.read_bytes()
                self.refused(self.answer(flag, value), before)
        help_text = self.cli("answer", "--help").stdout
        self.assertNotIn("--scope", help_text)
        self.fixture["decisions"][0]["state"] = "settled"
        self.fake.write_text(json.dumps(self.fixture))
        self.refused(self.answer(), self.fake.read_bytes())

    def test_ambiguous_and_adapter_error(self):
        self.fixture["decisions"] *= 2
        self.fake.write_text(json.dumps(self.fixture))
        self.refused(self.answer(), self.fake.read_bytes())
        self.fake.write_text("not json")
        self.refused(self.answer(), self.fake.read_bytes())
        self.refused(self.cli("answer", "--run", "run-1", "--decision", "transport", "--option", "a",
                              env={**self.env, "WORKBENCH_DECIDE_ADAPTER": "unknown"}), self.fake.read_bytes())

    def test_check_answer(self):
        file = self.root / "answer.json"
        file.write_text(json.dumps(ANSWER))
        self.assertEqual(self.cli("check-answer", str(self.prompt), str(file)).returncode, 0)
        for key, value in [("decisionId", "wrong"), ("option", "missing"), ("scope", "broader"),
                           ("schema", "wrong"), ("promote", "yes"), ("note", False), ("extra", True)]:
            file.write_text(json.dumps({**ANSWER, key: value}))
            self.assertNotEqual(self.cli("check-answer", str(self.prompt), str(file)).returncode, 0)
        for key in ANSWER:
            invalid = dict(ANSWER)
            del invalid[key]
            file.write_text(json.dumps(invalid))
            self.assertNotEqual(self.cli("check-answer", str(self.prompt), str(file)).returncode, 0)

    def test_promote(self):
        file = self.root / "answer.json"
        file.write_text(json.dumps({**ANSWER, "promote": True}))
        before = {p: p.read_bytes() for p in (file, self.prompt, self.fake)}
        args = ("promote", str(self.prompt), str(file), "--granted-by", "human:fixture",
                "--granted-at", "2026-11-15T08:00:00Z")
        result = self.cli(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '{\n'
                         '  id = "transport";\n'
                         '  rule = "A — Reuse setup. Scope: Select the transport only.";\n'
                         '  source = "decision:transport BPH-66";\n'
                         '  grantedBy = "human:fixture";\n'
                         '  grantedAt = "2026-11-15T08:00:00Z";\n'
                         '}\n')
        self.assertEqual({p: p.read_bytes() for p in before}, before)
        for key, value in [("promote", False), ("option", "missing"), ("scope", "broader"),
                           ("decisionId", "wrong"), ("schema", "wrong"), ("promote", "true")]:
            with self.subTest(key=key, value=value):
                file.write_text(json.dumps({**ANSWER, "promote": True, key: value}))
                self.refused(self.cli(*args), before[self.fake])
        file.write_text(json.dumps({**ANSWER, "promote": True}))
        for flag, value in [("--granted-by", ""), ("--granted-at", "2026-11-15"),
                            ("--granted-at", "2026-02-30T00:00:00Z")]:
            self.refused(self.cli(*args, flag, value), before[self.fake])
        for missing in ("--granted-by", "--granted-at"):
            shortened = list(args)
            index = shortened.index(missing)
            del shortened[index:index + 2]
            self.refused(self.cli(*shortened), before[self.fake])
        decision = copy.deepcopy(DECISION)
        del decision["assignment"]["issue"]
        literal = decide.promote(decision, {**ANSWER, "promote": True}, "human:fixture",
                                 "2026-11-15T08:00:00+00:00")
        self.assertIn('source = "decision:transport";', literal)
        decision["decisionId"] = "Bad ID"
        with self.assertRaisesRegex(ValueError, "token"):
            decide.promote(decision, {**ANSWER, "decisionId": "Bad ID", "promote": True},
                           "human:fixture", "2026-11-15T08:00:00Z")

    def test_nix_quoting(self):
        self.assertEqual(decide.nix_string('"${value}\\\n\t雪'),
                         r'"\"\${value}\\\n\t雪"')

    def test_invalid_decision_contract(self):
        with self.assertRaises(ValueError):
            decide.from_outcome({"kind": "result"})
        for key, value in [("scope", ""), ("decisionId", ""), ("recommendation", "missing"),
                           ("options", DECISION["options"][:1]), ("assignment", {"repo": ""}),
                           ("schema", "wrong"), ("extra", True)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                decide.validate_decision({**DECISION, key: value})
        invalid = copy.deepcopy(DECISION)
        invalid["options"][1]["id"] = "a"
        with self.assertRaises(ValueError):
            decide.validate_decision(invalid)
        invalid["assignment"]["run"] = "another-run"
        self.fixture["decisions"][0]["prompt"] = decide.prompt({**DECISION, "assignment": invalid["assignment"]})
        self.fake.write_text(json.dumps(self.fixture))
        self.refused(self.answer(), self.fake.read_bytes())

    def test_cotal_opt_in_and_stubbed_json_lines(self):
        # No Cotal binary, credentials or service calls. Constructor guard cannot
        # be bypassed by importing the isolated adapter directly.
        with patch.dict(os.environ, {}, clear=True), patch("decide_cotal.subprocess.run") as run:
            with self.assertRaises(ValueError):
                CotalAdapter()
            run.assert_not_called()
        env = {k: v for k, v in self.env.items() if k != "WORKBENCH_DECIDE_FAKE"}
        result = self.cli("queue", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("UNVERIFIED", result.stderr)
        responses = [json.dumps({"runId": "run-1"}) + "\n", json.dumps({
            "step": "/checkpoint:choose#0", "effect": "checkpoint", "state": "pending",
            "asks": self.prompt.read_text()}) + "\n", ""]
        with patch.dict(os.environ, {"WORKBENCH_DECIDE_ADAPTER": "cotal"}), \
                patch.object(CotalAdapter, "call", side_effect=responses) as call:
            adapter = CotalAdapter()
            rows = decide.open_decisions(adapter)
            self.assertEqual(rows[0]["decision"], DECISION)
            adapter.answer("run-1", rows[0]["stepKey"], ANSWER)
            self.assertEqual(call.call_args_list[0].args, ("ps", "--json"))
            self.assertEqual(call.call_args_list[1].args, ("journal", "run-1", "--json"))
            self.assertEqual(call.call_args_list[2].args,
                             ("answer", "run-1", "/checkpoint:choose#0", "--value", json.dumps(ANSWER)))


if __name__ == "__main__":
    unittest.main()
