import json
import os
from pathlib import Path
import subprocess
import sys
import random
import string

scanner = sys.argv[1]
rng = random.Random(9421)
secret = "ghp_" + "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(36))
root = Path.cwd() / "fixture"
root.mkdir()
os.chdir(root)


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True)


def run(mode="worktree", expected=0, *extra):
    report = root.parent / "safe.json"
    result = subprocess.run([scanner, "--mode", mode, "--report", str(report), *extra], capture_output=True)
    output = result.stdout + result.stderr + (report.read_bytes() if report.exists() else b"")
    for i in range(len(secret) - 7):
        assert secret[i:i + 8].encode() not in output, "secret substring escaped"
    assert result.returncode == expected, (result.returncode, result.stdout, result.stderr)
    findings = json.loads(result.stdout)
    assert all(set(f) == {"RuleID", "File", "StartLine", "Fingerprint"} for f in findings)
    return findings


git("init", "-q")
git("config", "user.email", "fixture@example.invalid")
git("config", "user.name", "Fixture")
Path("clean.txt").write_text("ordinary text\n")
git("add", ".")
git("commit", "-qm", "clean")
run()
run("staged")
Path("credential.txt").write_text(secret + "\n")
git("add", "credential.txt")
findings = run("staged", 1)
assert findings
run("worktree", 1)
# Baseline contains only sanitized fields, never a raw candidate.
Path("baseline.json").write_text(json.dumps(run("worktree", 1)))
run("worktree", 0, "--baseline", "baseline.json")
Path("ignore.txt").write_text(findings[0]["Fingerprint"] + "\n")
run("staged", 0, "--ignore-file", "ignore.txt")
# Environment-layer TOML can extend upstream rules with narrow allowlists.
Path("allowed.toml").write_text('[extend]\nuseDefault = true\n[[allowlists]]\ndescription = "reviewed synthetic placeholder"\nregexTarget = "secret"\nregexes = ["' + secret + '"]\n')
run("worktree", 0, "--config", "allowed.toml")
# Inline allow annotations are the shared scanner's exception mechanism.
Path("credential.txt").write_text(secret + " # betterleaks:allow -- synthetic fixture\n")
git("add", "credential.txt")
run("staged")
run("worktree")
# Staged scan must ignore an unstaged leak, and vice versa.
Path("credential.txt").write_text(secret + "\n")
run("staged")
run("worktree", 1)
git("add", "credential.txt")
git("commit", "-qm", "synthetic")
Path("credential.txt").unlink()
git("add", "-u")
git("commit", "-qm", "remove")
run("history", 1)
run()
# Nested repositories and symlink targets never belong to this repo's scan.
Path("nested").mkdir()
subprocess.run(["git", "init", "-q", "nested"], check=True)
Path("nested/credential.txt").write_text(secret)
subprocess.run(["git", "-C", "nested", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "commit", "--allow-empty", "-qm", "nested"], check=True)
git("add", "nested")
run()
Path("link").symlink_to(root / "nested/credential.txt")
git("add", "link")
run()
# A sandbox/store source has no .git. Honor .gitmodules there too.
source = root.parent / "source"
source.mkdir()
(source / ".gitmodules").write_text('[submodule "nested"]\n path = nested\n url = ./nested\n')
(source / "nested").mkdir()
(source / "nested/credential.txt").write_text(secret)
run("worktree", 0, "--source", str(source))
(source / "credential.txt").write_text(secret)
result = run("worktree", 1, "--source", str(source))
print(json.dumps(result, indent=2))
# Broken config fails closed without reflecting input or secret diagnostics.
Path("bad.toml").write_text(secret)
run_result = subprocess.run([scanner, "--config", str(root / "bad.toml")], capture_output=True)
assert run_result.returncode == 2
assert secret.encode() not in run_result.stdout + run_result.stderr
