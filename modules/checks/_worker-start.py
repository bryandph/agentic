"""Sandbox fixtures: no live Herdr, trust store, network or model."""
import json
import os
import shlex
from pathlib import Path
import subprocess
import sys
import tempfile


with tempfile.TemporaryDirectory() as root:
    root = Path(root)
    bindir = root / "bin"
    bindir.mkdir()
    env = dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ["PATH"], FIXTURE=str(root))

    def executable(name, source):
        path = bindir / name
        path.write_text("#!" + sys.executable + "\n" + source)
        path.chmod(0o755)

    executable("workbench-worktree-setup", '''import os,sys
assert sys.argv[1] == "--check"
case = os.environ["CASE"]
if case in ("setup-missing", "setup-failed"):
    print("worktree setup " + case, file=sys.stderr)
    sys.exit(2 if case == "setup-missing" else 1)
''')
    executable("launcher", '''import os,sys,json
from pathlib import Path
root = Path(os.environ["FIXTURE"])
(root / "argv").write_text(json.dumps(sys.argv[1:]))
if os.environ["CASE"] == "exit":
    print("\\n".join("old line " + str(i) for i in range(60)))
    print("\\x1b[31mOption '--prompt' argument is ambiguous\\x1b[0m", file=sys.stderr)
    sys.exit(2)
if os.environ["CASE"] == "trust-idle":
    print("\\n".join("old line " + str(i) for i in range(60)))
    for i in range(30): print("row" + str(i) + ": " + "abcdef😀" * 100)
    print("─" * 3000)
    print("\\x1b[35mTrust project folder?\\x1b[0m")
    print("─" * 3000)
''')
    executable("herdr", '''import json,os,sys,subprocess
from pathlib import Path
root = Path(os.environ["FIXTURE"])
case = os.environ["CASE"]
a = sys.argv[1:]
with (root / "calls").open("a") as f: f.write(json.dumps(a) + "\\n")
launched = (root / "launched").exists()
info = dict(workspace_id="w-fixture", cwd=str(root), agent=None, agent_status=None)
if launched and case in ("started", "blocked", "trust-idle"):
    info.update(agent="pi", agent_status={"started":"working", "blocked":"blocked", "trust-idle":"idle"}[case],
                agent_session={"value":"native-session.jsonl"})
if a[:2] == ["pane", "run"]:
    if case == "run-rejected": sys.exit(1)
    assert not a[3].startswith("exec ")
    (root / "launched").touch()
    result = subprocess.run(a[3], shell=True, capture_output=True, text=True)
    (root / "tail").write_text(result.stdout + result.stderr)
    print(json.dumps({"result": {}}))
elif a[:2] == ["pane", "get"]:
    if case == "pane-missing" or (case == "vanished" and launched): sys.exit(1)
    if case == "wrong-cwd": info["cwd"] = "/wrong"
    if case == "occupied": info["agent"] = "pi"
    print(json.dumps({"result":{"pane":info}}))
elif a[:2] == ["agent", "get"]:
    print(json.dumps({"result":{"agent":info}}))
elif a[:2] == ["pane", "read"]:
    print((root / "tail").read_text() if (root / "tail").exists() else "")
elif a[:2] == ["pane", "process-info"]:
    print(json.dumps({"result":{"process_info":{"shell_pid":1,
      "foreground_processes":[{"pid":1 if (not launched and case != "busy-shell") or case == "exit" else 2}]}}}))
elif a[:2] == ["agent", "wait"]:
    assert a[3:7] == ["--until", "working", "--until", "blocked"]
    sys.exit(1)
elif a[:2] == ["agent", "explain"]:
    print(json.dumps({"state":"idle", "fallback_reason":"default_known_agent_idle_fallback",
      "visible_blocker":False, "visible_idle":False, "visible_working":False,
      "manifest_version":"2026.10.01.1", "matched_rule":None,
      "evaluated_rules":[{"evidence":{"region_preview":"sensitive buffer" * 5000}}]}))
else: raise AssertionError(a)
''')
    prompt = root / "prompt with ' quotes.md"
    prompt.write_text("---\nissue: fixture\n---\n")
    weird = "spaces ' \" $HOME ; & \\ \n ---"
    for case, status, code in [("setup-missing", "setup-failed", 30),
                                ("setup-failed", "setup-failed", 30),
                                ("prompt-missing", "launch-failed", 20),
                                ("pane-missing", "launch-failed", 20),
                                ("wrong-cwd", "launch-failed", 20),
                                ("occupied", "launch-failed", 20),
                                ("busy-shell", "launch-failed", 20),
                                ("run-rejected", "launch-failed", 20),
                                ("exit", "launch-failed", 20),
                                ("blocked", "blocked", 10),
                                ("started", "started", 0),
                                ("vanished", "launch-failed", 20),
                                ("timeout", "launch-failed", 20),
                                ("trust-idle", "not-started", 11)]:
        for name in ("launched", "tail", "calls", "argv"):
            (root / name).unlink(missing_ok=True)
        result = subprocess.run([sys.argv[1], "--pane", "w:p", "--worktree", str(root),
                                 "--timeout", "0.8", "--", "launcher", "--prompt-file",
                                 str(prompt) if case != "prompt-missing" else "absent", weird, "---"],
                                env=dict(env, CASE=case), capture_output=True, text=True)
        assert result.returncode == code, (case, result)
        record = json.loads(result.stdout)
        assert record["status"] == status, (case, record)
        assert len(record["evidence"].splitlines()) <= 40
        assert "\x1b" not in record["evidence"]
        for field in ("evidence", "diagnostics"):
            assert len(record[field].encode("utf-8")) <= 4096, (case, field)
            assert all(len(line) <= 240 for line in record[field].splitlines()), (case, field)
        if case.startswith("setup-") or case in ("prompt-missing", "pane-missing", "wrong-cwd", "occupied", "busy-shell", "run-rejected"):
            assert not (root / "launched").exists()
        else:
            calls = [json.loads(line) for line in (root / "calls").read_text().splitlines()]
            assert sum(call[:2] == ["pane", "run"] for call in calls) == 1
            assert json.loads((root / "argv").read_text())[-2:] == [weird, "---"]
        if case == "exit":
            assert "Option '--prompt' argument is ambiguous" in record["evidence"], record
            assert "foreground returned to shell" in record["reason"]
        if case == "started":
            assert record["session"] == "native-session.jsonl"
            expected = "workbench-worker-start: launching: " + shlex.join(
                ["launcher", "--prompt-file", str(prompt), weird, "---"])
            assert expected in (root / "tail").read_text()
            assert "workbench-worker-start: launching: launcher --prompt-file" in record["evidence"]
        if case == "trust-idle":
            assert record["agentStatus"] == "idle"
            assert record["fallback_reason"] == "default_known_agent_idle_fallback"
            assert record["visible_blocker"] is False
            assert "Trust project folder?" in record["evidence"]
            assert "─…(×3000)" in record["evidence"]
            details = json.loads(record["diagnostics"])
            assert set(details) == {"state", "fallback_reason", "visible_blocker", "visible_idle",
                                    "visible_working", "manifest_version", "matched_rule"}
            assert details["manifest_version"] == "2026.10.01.1"
            assert "region_preview" not in record["diagnostics"]
        if case == "timeout":
            assert "timeout" in record["reason"]
        print(case, "ok")

    # An unavailable setup command must also yield one structured record.
    (bindir / "workbench-worktree-setup").unlink()
    result = subprocess.run([sys.argv[1], "--pane", "w:p", "--worktree", str(root),
                             "--", "launcher"], env=env, capture_output=True, text=True)
    assert result.returncode == 30, result
    record = json.loads(result.stdout)
    assert record["status"] == "setup-failed"
    assert "No such file" in record["diagnostics"]
    print("setup-command-unavailable ok")
