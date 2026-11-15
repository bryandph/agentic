"""Offline fixture adapter. Not a production decision store."""

import fcntl
import json
import os

from decide import check_answer, parse_prompt
from outcome import parse_json


class FakeAdapter:
    def __init__(self):
        self.filename = os.environ.get("WORKBENCH_DECIDE_FAKE")
        if not self.filename:
            raise ValueError("fake adapter requires WORKBENCH_DECIDE_FAKE")

    @staticmethod
    def load(source):
        value = parse_json(source.read())
        if not isinstance(value, dict) or set(value) != {"decisions", "answers"}:
            raise ValueError("invalid fake fixture")
        if not isinstance(value["decisions"], list) or not isinstance(value["answers"], list):
            raise ValueError("invalid fake fixture lists")
        for row in value["decisions"]:
            if not isinstance(row, dict) or set(row) != {"run", "stepKey", "prompt", "state"}:
                raise ValueError("invalid fake decision row")
            if row["state"] not in ("open", "settled") or not isinstance(row["prompt"], str):
                raise ValueError("invalid fake decision state or prompt")
        return value

    def open_decisions(self):
        with open(self.filename) as source:
            fcntl.flock(source, fcntl.LOCK_SH)
            fixture = self.load(source)
        return [{"run": row["run"], "stepKey": row["stepKey"], "decision": parse_prompt(row["prompt"])}
                for row in fixture["decisions"] if row["state"] == "open"]

    def answer(self, run, step_key, value):
        with open(self.filename, "r+") as source:
            fcntl.flock(source, fcntl.LOCK_EX)
            fixture = self.load(source)
            rows = [r for r in fixture["decisions"] if r["run"] == run and r["stepKey"] == step_key]
            if len(rows) != 1 or rows[0]["state"] != "open":
                raise ValueError("fake decision is not uniquely open")
            check_answer(parse_prompt(rows[0]["prompt"]), value)
            rows[0]["state"] = "settled"
            fixture["answers"].append({"run": run, "stepKey": step_key, "value": value})
            encoded = json.dumps(fixture) + "\n"
            source.seek(0)
            source.write(encoded)
            source.truncate()
