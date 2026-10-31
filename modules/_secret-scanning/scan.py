"""Safe Betterleaks boundary: raw scanner streams never leave this process."""
import argparse
import configparser
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def git(root, *args):
    return subprocess.check_output([GIT, "-C", str(root), *args], stderr=subprocess.DEVNULL)


def scan(args):
    root = Path(args.source).resolve()
    baseline = args.baseline or BASELINE
    ignore = args.ignore_file or IGNORE
    config = str((root / (args.config or CONFIG)).resolve())
    with tempfile.TemporaryDirectory(prefix="agentic-secret-scan-") as tmp:
        tmp = Path(tmp)
        report = tmp / "report.json"
        command = [SCANNER]
        if args.mode == "worktree":
            # A private snapshot avoids .git, untracked build products, symlink
            # escapes and gitlinks. Source-store scans have no Git metadata.
            snapshot = tmp / "source"
            snapshot.mkdir()
            if (root / ".git").exists():
                entries = git(root, "ls-files", "--stage", "-z").decode().split("\0")
                files = [e.split("\t", 1)[1] for e in entries if e and e.startswith("100")]
            else:
                submodules = []
                if (root / ".gitmodules").exists():
                    parser = configparser.ConfigParser()
                    parser.read(root / ".gitmodules")
                    submodules = [str(Path(s["path"])) for s in parser.values() if "path" in s]
                files = []
                for parent, dirs, names in os.walk(root, followlinks=False):
                    dirs[:] = sorted(d for d in dirs if d != ".git" and not (Path(parent) / d).is_symlink()
                                     and not (Path(parent) / d / ".git").exists()
                                     and str((Path(parent) / d).relative_to(root)) not in submodules)
                    files.extend(str((Path(parent) / n).relative_to(root)) for n in sorted(names))
            for name in sorted(set(files)):
                source = root / name
                if source.is_file() and not source.is_symlink():
                    dest = snapshot / name
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, dest)
            command += ["dir", "."]
            cwd = snapshot
        else:
            cwd = root
            command += ["git", "."]
            if args.mode == "staged":
                command += ["--pre-commit", "--staged"]
            else:
                command += ["--log-opts=--all"]
        command += ["--redact=100", "--no-banner", "--no-color", "--log-level=error",
                    "--config", config, "--report-format=json", "--report-path", str(report),
                    "--exit-code=42"]
        # Disable implicit repo-local ignore discovery: exceptions are explicit.
        empty_ignore = tmp / "empty.ignore"
        empty_ignore.touch()
        command += ["--gitleaks-ignore-path", str((root / ignore).resolve()) if ignore else str(empty_ignore)]
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(("BETTERLEAKS_", "GITLEAKS_", "GIT_"))}
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_CONFIG_GLOBAL"] = os.devnull
        result = subprocess.run(command, cwd=cwd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode not in (0, 42):
            raise RuntimeError("scanner failed")
        raw = json.loads(report.read_text()) if report.exists() else []
        # Baselines deliberately contain no Match/Secret/author/message fields.
        known = set()
        if baseline:
            known = {f["Fingerprint"] for f in json.loads((root / baseline).read_text())}
        findings = [{"RuleID": f["RuleID"], "File": f["File"], "StartLine": f["StartLine"],
                     "Fingerprint": f["Fingerprint"]} for f in (raw or [])
                    if f["Fingerprint"] not in known]
        findings.sort(key=lambda f: (f["File"], f["StartLine"], f["RuleID"], f["Fingerprint"]))
        output = json.dumps(findings, indent=2) + "\n"
        if args.report:
            Path(args.report).write_text(output)
        sys.stdout.write(output)
        return 1 if findings else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["staged", "worktree", "history"], default="worktree")
    parser.add_argument("--source", default=".")
    parser.add_argument("--config")
    parser.add_argument("--baseline")
    parser.add_argument("--ignore-file")
    parser.add_argument("--report", help="write the same field-filtered JSON emitted to stdout")
    args = parser.parse_args()
    try:
        return scan(args)
    except Exception:
        # Exceptions and tool diagnostics can contain input data. Fail closed,
        # emitting neither tracebacks nor raw tool errors.
        print("agentic-secret-scan: scan failed (diagnostics suppressed)", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
