"""Offline CLI fixtures; the only remote is a temporary local bare repository."""

import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).parent / "outcome.py"
SPEC = importlib.util.spec_from_file_location("outcome", SOURCE)
outcome = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(outcome)
OUTCOME = sys.argv.pop(1) if len(sys.argv) > 1 else None
VERIFY = sys.argv.pop(1) if len(sys.argv) > 1 else None

BODIES = {
    "result": {"evidence": [{"type": "ci", "system": "fixture", "pipeline": "1", "status": "passed"}]},
    "decision": {"id": "choose", "question": "Which?", "context": "Two choices.", "options": [
        {"id": "a", "label": "A", "consequences": "First."},
        {"id": "b", "label": "B", "consequences": "Second."}], "recommendation": "a", "scope": "Only the choice."},
    "approval": {"id": "deploy", "action": "deploy", "artifact": "sha", "reason": "Approval required."},
    "environment": {"code": "nix-relativeworktrees", "detail": "Setup refused."},
    "external": {"waitingOn": "upstream", "deadline": "2026-11-15T00:00:00Z"},
    "failed": {"attempted": "Build", "error": "Build failed.\nMore context.", "externalEffects": False},
    "handoff": {"to": "coordinator", "reason": "Crosses repository boundary."},
}


def example(kind):
    return {"schema": "agentic.outcome/1", "kind": kind,
            "assignment": {"repo": "agentic", "issue": "BPH-66"},
            "summary": "Fixture outcome.", outcome.BODIES[kind]: copy.deepcopy(BODIES[outcome.BODIES[kind]])}


class Contract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.file = self.root / "outcome.json"

    def cli(self, command, *args, value=None, stdin=None, env=None):
        if value is not None:
            self.file.write_text(json.dumps(value))
        base = ([VERIFY] if command == "verify" else [OUTCOME]) if OUTCOME else [
            sys.executable, str(SOURCE), "verify" if command == "verify" else "outcome"]
        if command != "verify":
            base += [command]
        return subprocess.run(base + list(args), input=stdin, text=True, capture_output=True, check=False, env=env)

    def test_all_kinds_and_required_paths(self):
        schema = json.loads(outcome.SCHEMA_PATH.read_text())
        for kind, body in outcome.BODIES.items():
            value = example(kind)
            with self.subTest(kind=kind):
                self.assertEqual(outcome.validate(value), [])
                self.assertEqual(self.cli("validate", str(self.file), value=value).returncode, 0)
                for field in schema["$defs"][body]["required"]:
                    invalid = copy.deepcopy(value)
                    del invalid[body][field]
                    result = self.cli("validate", str(self.file), value=invalid)
                    self.assertEqual(result.returncode, 1)
                    self.assertIn(f"/{body}/{field}: required", result.stderr)
                for field in ["schema", "kind", "assignment", "summary", body]:
                    invalid = copy.deepcopy(value)
                    del invalid[field]
                    result = self.cli("validate", str(self.file), value=invalid)
                    self.assertEqual(result.returncode, 1)
                    self.assertIn(f"/{field}:", result.stderr)
                invalid = copy.deepcopy(value)
                invalid["kind"] = "result" if kind != "result" else "failed"
                self.assertEqual(self.cli("validate", str(self.file), value=invalid).returncode, 1)
                invalid = copy.deepcopy(value)
                invalid["unrelated"] = True
                self.assertEqual(self.cli("validate", str(self.file), value=invalid).returncode, 1)

    def test_validation_edges(self):
        for summary in ["a" * 501, "two\nparagraphs", "a\rb", "a\u2028b", "trailing\n", 42]:
            value = example("handoff")
            value["summary"] = summary
            self.assertTrue(any(e.startswith("/summary:") for e in outcome.validate(value)))
        for value in [None, [], "result", {"kind": "unrecognized"}]:
            self.assertTrue(outcome.validate(value))
        decision = example("blocked:decision")
        decision["decision"]["recommendation"] = "missing"
        self.assertIn("/decision/recommendation:", "\n".join(outcome.validate(decision)))
        decision["decision"]["options"][1]["id"] = "a"
        self.assertIn("/decision/options:", "\n".join(outcome.validate(decision)))
        for deadline in ["2026-11-15", "tomorrow", "2026-02-30T00:00:00Z", "2026-11-15T00:00:00", "2026-11-15T00:00:00+00:60"]:
            value = example("blocked:external")
            value["external"]["deadline"] = deadline
            self.assertIn("/external/deadline:", "\n".join(outcome.validate(value)))
        for item in [{"type": "file", "path": "x", "sha256": "bad"},
                     {"type": "file", "path": "x", "sha256": "0" * 64 + "\n"},
                     {"type": "check", "attr": "test", "exitCode": True},
                     {"type": "git-ref", "remote": "x", "ref": "HEAD", "sha": "bad"},
                     {"type": "mystery"}]:
            value = example("result")
            value["result"]["evidence"] = [item]
            self.assertIn("/result/evidence/0/", "\n".join(outcome.validate(value)))
        value = example("result")
        value["result"]["evidence"] = []
        self.assertTrue(outcome.validate(value))
        result = self.cli("validate", "-", stdin=json.dumps(example("result")))
        self.assertEqual(result.returncode, 0, result.stderr)
        for text in ["not json", "NaN"]:
            self.assertEqual(self.cli("validate", "-", stdin=text).returncode, 1)

    def test_extract(self):
        block = "```agentic-outcome\n" + json.dumps(example("handoff")) + "\n```\n"
        for count in [0, 1, 2]:
            self.file.write_text("Message.\n" + block * count)
            result = self.cli("extract", str(self.file))
            self.assertEqual(result.returncode, 0 if count == 1 else 1, result.stderr)
            if count == 1:
                self.assertEqual(json.loads(result.stdout), example("handoff"))
        for message in ["```agentic-outcome\nnot JSON\n```", "```agentic-outcome\n[]\n```"]:
            self.file.write_text(message)
            self.assertEqual(self.cli("extract", str(self.file)).returncode, 1)

    def test_yield_and_ask(self):
        for kind in outcome.BODIES:
            result = self.cli("yield", str(self.file), value=example(kind))
            self.assertEqual(result.returncode, 0, result.stderr)
            record = json.loads(result.stdout)
            expected = {
                "result": {"status": "done", "note": "Fixture outcome."},
                "blocked:decision": {"status": "blocked", "note": "blocked:decision choose"},
                "blocked:approval": {"status": "blocked", "note": "blocked:approval deploy"},
                "blocked:environment": {"status": "blocked", "note": "blocked:environment nix-relativeworktrees"},
                "blocked:external": {"status": "blocked", "note": "blocked:external upstream"},
                "failed": {"status": "blocked", "note": "failed: Build failed."},
                "handoff": {"status": "handoff", "to": "coordinator", "note": "Crosses repository boundary."},
            }[kind]
            self.assertEqual(record, expected)
        self.assertEqual(json.loads(self.cli("ask-schema").stdout), outcome.ASK_SCHEMA)
        for kind in outcome.BODIES:
            value = example(kind)
            body = value[outcome.BODIES[kind]]
            field = {"result": "summary", "blocked:decision": "id", "blocked:approval": "id",
                     "blocked:environment": "code", "blocked:external": "waitingOn",
                     "failed": "error", "handoff": "reason"}[kind]
            target = value if kind == "result" else body
            target[field] = "x" * 400
            note = outcome.yield_record(value)["note"]
            self.assertEqual(len(note), 200)
            self.assertTrue(note.endswith("…"))
            if kind != "result":
                target[field] = "first\nsecond"
                self.assertNotIn("\n", outcome.yield_record(value)["note"])

    def verify(self, items, expected):
        value = example("result")
        value["result"]["evidence"] = items
        result = self.cli("verify", str(self.file), value=value)
        self.assertEqual(result.returncode, expected, result.stderr)
        records = json.loads(result.stdout)["items"]
        self.assertEqual([i["index"] for i in records], list(range(len(items))))
        return records

    def test_file_and_deferred(self):
        data = self.root / "data"
        data.write_bytes(b"fixture\n")
        file_item = {"type": "file", "path": str(data), "sha256": hashlib.sha256(data.read_bytes()).hexdigest()}
        self.assertEqual(self.verify([file_item], 0)[0]["verdict"], "ok")
        file_item["sha256"] = "0" * 64
        self.assertEqual(self.verify([file_item], 1)[0]["verdict"], "mismatch")
        deferred = [BODIES["result"]["evidence"][0], {"type": "flux", "kind": "Kustomization", "name": "fixture", "namespace": "flux-system", "revision": "main@sha1:abc"}]
        for record in self.verify(deferred, 2):
            self.assertEqual(record["verdict"], "unknown")
            self.assertEqual(record["detail"], "probe not configured (deferred)")
        self.verify([file_item] + deferred, 1)  # mismatch takes precedence
        data.unlink()
        self.assertEqual(self.verify([file_item], 2)[0]["verdict"], "unknown")
        check = {"type": "check", "attr": "outcome-contract", "exitCode": 0}
        self.assertEqual(self.verify([check], 2)[0]["detail"], "not re-run")
        self.assertEqual(self.cli("verify", str(self.file), value=example("handoff")).returncode, 0)
        external = example("blocked:external")
        external["external"]["evidence"] = deferred[0]
        self.assertEqual(self.cli("verify", str(self.file), value=external).returncode, 2)

    def test_git_remote(self):
        source = self.root / "source"
        remote = self.root / "remote.git"
        source.mkdir()
        def git(*args):
            return subprocess.run(["git", *map(str, args)], cwd=source, check=True, capture_output=True, text=True).stdout.strip()
        git("init", "-b", "main")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--allow-empty", "-m", "fixture")
        sha = git("rev-parse", "HEAD")
        git("clone", "--bare", source, remote)
        item = {"type": "git-ref", "remote": str(remote), "ref": "refs/heads/main", "sha": sha}
        self.assertEqual(self.verify([item], 0)[0]["observed"], [sha])
        item["sha"] = "0" * 40
        self.assertEqual(self.verify([item], 1)[0]["verdict"], "mismatch")
        item["ref"] = "refs/heads/missing"
        self.assertEqual(self.verify([item], 1)[0]["observed"], [])

    def test_missing_nix(self):
        value = example("result")
        value["result"]["evidence"] = [{"type": "check", "attr": "outcome-contract", "exitCode": 0}]
        result = self.cli("verify", "--rerun-checks", str(self.file), value=value,
                          env={**os.environ, "PATH": ""})
        self.assertEqual(result.returncode, 2, result.stderr)
        item = json.loads(result.stdout)["items"][0]
        self.assertEqual(item["verdict"], "unknown")
        self.assertEqual(item["detail"], "nix not on PATH")

    def test_opt_in_check_command(self):
        # Stub subprocess at the probe boundary: no actual Nix evaluation/network.
        calls = []
        def run(args):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, "aarch64-darwin" if args[1] == "eval" else "", "")
        original = outcome.run_command
        outcome.run_command = run
        self.addCleanup(setattr, outcome, "run_command", original)
        item = {"type": "check", "attr": "outcome-contract", "exitCode": 0}
        self.assertEqual(outcome.probe(item, False)[0], "unknown")
        self.assertEqual(calls, [])
        self.assertEqual(outcome.probe(item, True)[0], "ok")
        self.assertEqual(calls[-1], ["nix", "build", "--no-link", "--", ".#checks.aarch64-darwin.outcome-contract"])
        item["flake"] = "/fixture"
        item["exitCode"] = 1
        self.assertEqual(outcome.probe(item, True)[0], "mismatch")
        self.assertEqual(calls[-1][-1], "/fixture#checks.aarch64-darwin.outcome-contract")


if __name__ == "__main__":
    unittest.main()
