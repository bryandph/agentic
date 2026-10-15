"""Bounded CLI controls: all Nix queries/copies are stubs, never uploads.

Usage: python3 ci-cache-query.py /path/to/bash /path/to/agentic-ci-cache.sh
"""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

bash, source = sys.argv[1:3]
root = "/nix/store/" + "0" * 32 + "-output"
reference = "/nix/store/" + "1" * 32 + "-reference"
count = 0
with tempfile.TemporaryDirectory() as tmp:
    directory = Path(tmp)
    binaries = directory / "bin"
    binaries.mkdir()
    for name in ("jq", "date", "cat", "mktemp", "rm", "env", "tr", "sed", "uname"):
        executable = shutil.which(name)
        if not executable:
            raise RuntimeError(f"missing test dependency: {name}")
        (binaries / name).symlink_to(executable)
    marker = directory / "copied"
    nix = binaries / "nix"
    nix.write_text(f'''#!{bash}
case "$1" in
 path-info)
   case "$QUERY_MODE" in
     fail) echo FIXTURE-DIAGNOSTIC >&2; exit 42 ;;
     partial) echo "$ROOT"; exit 42 ;;
     mixed) printf '%s\\n' "$ROOT" garbage; exit 42 ;;
     empty) exit 0 ;;
   esac
   printf '%s\\n' "$ROOT" "$REFERENCE" ;;
 copy)
   printf '%s\\n' "$@" > "$MARKER"
   echo FIXTURE-DIAGNOSTIC >&2
   [ "$COPY_MODE" != fail ] ;;
 *) exit 99 ;;
esac
''')
    nix.chmod(0o755)
    contract = {"version": 1, "profiles": {"nix": {
        "protectedWriteEndpoint": "file:///fixture/protected",
        "pullRequestWriteEndpoint": "file:///fixture/quarantine"}}}

    def run(tier, query="valid", roots=None, bound="2000", copied=False,
            copy_mode="ok", configured=None):
        global count
        marker.unlink(missing_ok=True)
        before = set(directory.iterdir())
        env = {"PATH": str(binaries), "HOME": tmp, "TMPDIR": tmp,
               "CI_REPO": "fixture/consumer", "AGENTIC_CI_TRUST_TIER": tier,
               "AGENTIC_CI_CACHE_CONTRACT": json.dumps(configured or contract),
               "AGENTIC_NIX_PUBLISH_MAX_PATHS": bound,
               "QUERY_MODE": query, "COPY_MODE": copy_mode,
               "ROOT": root, "REFERENCE": reference, "MARKER": str(marker)}
        process = subprocess.run(
            [bash, "-euo", "pipefail", source, "nix", "publish",
             *(roots if roots is not None else [root])],
            env=env, text=True, capture_output=True, timeout=5)
        assert process.returncode == 0, (process.returncode, process.stderr)
        lines = process.stdout.splitlines()
        assert len(lines) == 1, process.stdout
        report = json.loads(lines[0])
        assert report["trust_tier"] == tier
        assert marker.exists() == copied, (tier, query, report)
        assert "FIXTURE-DIAGNOSTIC" not in process.stdout + process.stderr
        assert set(directory.iterdir()) - before <= {marker}, "temporary query file leaked"
        if copied:
            arguments = marker.read_text().splitlines()
            assert root in arguments and reference not in arguments, arguments
            assert arguments[arguments.index("--to") + 1].endswith(
                "/protected" if tier == "protected" else "/quarantine")
            assert report["path_count"] == 2
            assert report["outcome"] == ("failed" if copy_mode == "fail" else "published")
        else:
            assert report["outcome"] in ("failed", "refused", "skipped-bound", "skipped")
        count += 1
        print(f"ok {count}: {tier} query={query} outcome={report['outcome']} copied={copied}")

    for tier in ("protected", "pull-request"):
        if "--query-failure-control" in sys.argv[3:]:
            run(tier, query="partial")
            continue
        run(tier, copied=True)
        run(tier, copied=True, copy_mode="fail")
        for mode in ("fail", "partial", "mixed", "empty"):
            run(tier, query=mode)
        run(tier, roots=[])
        for bound in ("0", "1", "bad", "-1", "1000000000"):
            run(tier, bound=bound)
        run(tier, bound="0002", copied=True)
        run(tier, configured={"version": 1, "profiles": {}})
        # Authentication remains required before a real transport is attempted.
        for scheme in ("https", "s3"):
            run(tier, configured={"version": 1, "profiles": {"nix": {
                "protectedWriteEndpoint": f"{scheme}://fixture.example/protected",
                "pullRequestWriteEndpoint": f"{scheme}://fixture.example/quarantine"}}})
        run(tier, configured={"version": 1, "profiles": {"nix": {
            "protectedWriteEndpoint": "file:///fixture/shared",
            "pullRequestWriteEndpoint": "file:///fixture/shared"}}})
    print(f"PASS {count} conventional cache CLI controls; no real copy executed")
