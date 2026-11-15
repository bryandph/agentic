"""UNVERIFIED Cotal 0.91 CLI adapter. Re-qualify after the pending upgrade.

Only this file knows the Cotal journal shape. No live calls belong in tests.
The 0.91 CLI reference documents JSON Lines: runId in ps; step, effect,
state and asks in journal. Pending checkpoints with asks are open pauses.
"""

import json
import os
import subprocess

from outcome import parse_json


class CotalAdapter:
    def __init__(self):
        if os.environ.get("WORKBENCH_DECIDE_ADAPTER") != "cotal":
            raise ValueError("UNVERIFIED cotal adapter requires WORKBENCH_DECIDE_ADAPTER=cotal")

    @staticmethod
    def call(*args):
        try:
            result = subprocess.run(["cotal", "run", *args], text=True, capture_output=True,
                                    timeout=30, check=False)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ValueError("cotal adapter unavailable; outcome unknown for an answer; inspect journal before retry") from exc
        if result.returncode:
            # Do not echo external stderr, credentials, or arbitrary service text.
            raise ValueError("cotal adapter command failed; inspect journal before retrying an answer")
        return result.stdout

    def rows(self, *args):
        rows = [parse_json(line) for line in self.call(*args).splitlines() if line.strip()]
        if any(not isinstance(row, dict) for row in rows):
            raise ValueError("invalid cotal JSON Lines response")
        return rows

    def open_decisions(self):
        from decide import parse_prompt
        decisions = []
        for run in self.rows("ps", "--json"):
            run_id = run.get("runId")
            if not isinstance(run_id, str) or not run_id or run_id.startswith("-"):
                raise ValueError("invalid cotal run id")
            if run.get("revoked") or run.get("revocationUnreadable"):
                raise ValueError("cotal run revoked or revocation unreadable")
            for row in self.rows("journal", run_id, "--json"):
                if row.get("effect") != "checkpoint" or row.get("state") != "pending":
                    continue
                asks = row.get("asks")
                if asks is None:
                    continue
                if not isinstance(asks, str):
                    raise ValueError("unrecognized cotal checkpoint asks shape")
                if "agentic-decision" not in asks:
                    continue  # An ordinary checkpoint, not a filed typed decision.
                decisions.append({"run": run_id, "stepKey": row.get("step"), "decision": parse_prompt(asks)})
        return decisions

    def answer(self, run, step_key, value):
        # Cotal performs the atomic single-use settlement and attribution. Never
        # retry a failed/uncertain call or turn it into an amend.
        self.call("answer", run, step_key, "--value", json.dumps(value))
