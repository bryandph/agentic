#!/usr/bin/env python3
"""Compare the resolved workspace declaration with the tree, read-only.

Reads only the resolved form ($WORKBENCH_WORKSPACE_MANIFEST, a JSON list of
{key, url, aliases, path, groups}) and reports:

  missing     a declared path that does not exist
  not-a-repo  a declared path that is not the top of a git repository
  origin      a checkout whose origin URL is neither the declared URL nor
              an alias (a checkout without origin counts too)
  undeclared  a top-level directory that is not declared, not a parent of
              a declared path, not ignored and not a dot-directory

Nothing is written: git is asked only `rev-parse --show-toplevel` and
`config --get`, with optional locks off.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

GIT_ENV = {**os.environ, "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"}


def git(directory: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(directory), *args],
        env=GIT_ENV,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
    )


def same_url(a: str, b: str) -> bool:
    # Exact match; only a trailing slash is treated as insignificant.
    # Equivalence across URL spellings is the override helper's job.
    return a.rstrip("/") == b.rstrip("/")


def audit(root: Path, entries: list[dict], ignore: set[str]) -> list[dict]:
    findings = []
    for entry in entries:
        key, path = entry["key"], entry["path"]
        checkout = root / path
        if not os.path.lexists(checkout):
            findings.append({"kind": "missing", "key": key, "path": path})
            continue
        top = git(checkout, "rev-parse", "--show-toplevel") if checkout.is_dir() else None
        if top is None or top.returncode != 0 or Path(top.stdout.strip()).resolve() != checkout.resolve():
            # Not a repository, or a plain directory inside an enclosing
            # one (typically the workspace repository itself).
            findings.append({"kind": "not-a-repo", "key": key, "path": path})
            continue
        origin = git(checkout, "config", "--get", "remote.origin.url").stdout.strip()
        accepted = [entry["url"], *entry["aliases"]]
        if not any(same_url(origin, url) for url in accepted):
            findings.append(
                {
                    "kind": "origin",
                    "key": key,
                    "path": path,
                    "origin": origin or None,
                    "expected": accepted,
                }
            )

    known = {entry["path"].split("/", 1)[0] for entry in entries}
    for child in sorted(root.iterdir()):
        name = child.name
        if not child.is_dir() or name.startswith(".") or name in known or name in ignore:
            continue
        findings.append({"kind": "undeclared", "key": None, "path": name})
    return findings


def describe(finding: dict) -> str:
    kind, key, path = finding["kind"], finding["key"], finding["path"]
    if kind == "missing":
        return f"missing     {key}: {path} does not exist"
    if kind == "not-a-repo":
        return f"not-a-repo  {key}: {path} is not a git repository"
    if kind == "origin":
        origin = finding["origin"] or "(no origin)"
        return f"origin      {key}: {path} has origin {origin}, declared {' or '.join(finding['expected'])}"
    return f"undeclared  {path}/ is neither declared nor ignored"


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="workspace-audit",
        description="Compare the workspace declaration with the checkouts under the root. Changes nothing.",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(os.environ.get("DEVENV_ROOT") or Path.cwd()),
        help="workspace root (default: $DEVENV_ROOT inside the workspace shell, else the current directory)",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=os.environ.get("WORKBENCH_WORKSPACE_MANIFEST"),
        help="resolved declaration (default: $WORKBENCH_WORKSPACE_MANIFEST)",
    )
    parser.add_argument(
        "--ignore",
        action="append",
        default=[],
        metavar="NAME",
        help="top-level name not to report as undeclared; repeatable, added to audit.ignore",
    )
    parser.add_argument("--strict", action="store_true", help="exit 1 when there are findings")
    parser.add_argument("--json", action="store_true", help="print the findings as JSON")
    parser.add_argument("--ignore-file", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()

    if args.manifest is None:
        parser.error("no manifest: WORKBENCH_WORKSPACE_MANIFEST is unset and --manifest was not given")
    if not args.root.is_dir():
        parser.error(f"root {args.root} is not a directory")
    entries = json.loads(args.manifest.read_text())
    ignore = set(args.ignore)
    if args.ignore_file is not None:
        ignore |= set(json.loads(args.ignore_file.read_text()))

    findings = audit(args.root, entries, ignore)
    if args.json:
        json.dump({"root": str(args.root.absolute()), "findings": findings}, sys.stdout, indent=2)
        print()
    elif findings:
        for finding in findings:
            print(describe(finding))
        print(f"{len(findings)} finding(s) under {args.root}")
    else:
        print(f"workspace under {args.root} matches the declaration")
    return 1 if args.strict and findings else 0


if __name__ == "__main__":
    sys.exit(main())
