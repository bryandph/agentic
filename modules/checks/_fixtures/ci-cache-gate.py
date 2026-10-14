"""Offline writer negative controls. Every nix/copy call is a stub; no uploads.
Run: python3 ci-cache-gate.py /path/to/bash /path/to/agentic-ci-cache.sh
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

bash, source = sys.argv[1:]
root = "/nix/store/" + "0" * 32 + "-fixture"
ref = "/nix/store/" + "1" * 32 + "-reference"
count = 0
with tempfile.TemporaryDirectory() as tmp:
    d = Path(tmp)
    bin_dir = d / "bin"
    bin_dir.mkdir()
    # Isolated capability set, so missing-tool is genuinely absent.
    for name in ("jq", "date", "cat", "mktemp", "chmod", "rm", "sort", "cmp", "grep", "env", "tr", "sed", "uname"):
        p = shutil.which(name)
        if not p:
            raise RuntimeError(f"missing test dependency: {name}")
        (bin_dir / name).symlink_to(p)
    marker = d / "copied"
    scanned = d / "scanned"
    policy_script = d / "policy"
    policy_script.write_text(f'''SCANNED={str(scanned)!r}
REF={ref!r}
POLICY_MODE="$(cat {str(d / 'policy-mode')!r})"
case "$POLICY_MODE" in
 allow) ;;
 deny) echo SECRET >&2; exit 1 ;;
 error) echo SECRET; exit 2 ;;
 other) exit 42 ;;
 mutate) chmod 600 "${{@: -1}}"; printf '%s\\n' "$REF" >> "${{@: -1}}" ;;
esac
printf '%s\\n' "$@" > "$SCANNED"
cat "${{@: -1}}" >> "$SCANNED"
''')
    store = bin_dir / "nix-store"
    store.write_text(f'''#!{bash}
case "$1" in
 --check-validity) [ "$QUERY_MODE" != unregistered ]; exit $? ;;
 --query)
 n=0; if [ -f "$QUERY_COUNTER" ]; then n="$(cat "$QUERY_COUNTER")"; fi
 n=$((n + 1)); echo "$n" > "$QUERY_COUNTER"
 case "$QUERY_MODE" in
 fail) exit 42 ;;
 partial) echo "$ROOT"; exit 42 ;;
 mixed) printf '%s\\n' "$ROOT" garbage; exit 42 ;;
 nul) printf '%s\\0\\n' "$ROOT"; exit 0 ;;
 cr) printf '%s\\r\\n' "$ROOT"; exit 0 ;;
 empty) exit 0 ;;
 missing-root) echo "$REF"; exit 0 ;;
 malformed) echo garbage; exit 0 ;;
 subpath) echo "$ROOT/bin"; exit 0 ;;
 traversal) echo "$ROOT/../$REF"; exit 0 ;;
 incomplete)
   if [ "$n" -eq 1 ]; then echo "$ROOT"; else printf '%s\\n' "$ROOT" "$REF"; fi; exit 0 ;;
 drift)
   if [ -f "$SCANNED" ]; then printf '%s\\n' "$ROOT" "$REF"; else echo "$ROOT"; fi; exit 0 ;;
 short) echo "$ROOT"; exit 0 ;;
 esac
 printf '%s\\n' "$ROOT" "$REF" ;;
 *) exit 2 ;;
esac
''')
    store.chmod(0o755)
    nix = bin_dir / "nix"
    nix.write_text(f'''#!{bash}
if [ "$1" = path-info ]; then printf '%s\\n' "$ROOT" "$REF"; exit 0; fi
[ "$1" = copy ] || exit 99
printf '%s\\n' "$@" > "$MARKER"
echo SECRET >&2
[ "$COPY_MODE" != fail ]
''')
    nix.chmod(0o755)
    policy = {"version": 1, "executable": bash, "argv": [str(policy_script)],
              "identity": "fixture-policy", "revision": "fixture-revision"}
    base = {"version": 1, "profiles": {"nix": {
        "protectedWriteEndpoint": "file:///fixture/protected",
        "pullRequestWriteEndpoint": "file:///fixture/quarantine",
        "publicationPolicy": policy}}}

    def run(tier, query="valid", policy_mode="allow", changes=None, roots=None,
            copied=False, copy_mode="ok"):
        global count
        marker.unlink(missing_ok=True)
        scanned.unlink(missing_ok=True)
        (d / "query-counter").unlink(missing_ok=True)
        (d / "policy-mode").write_text(policy_mode)
        contract = json.loads(json.dumps(base))
        if changes:
            changes(contract)
        env = {"PATH": str(bin_dir), "HOME": tmp, "TMPDIR": tmp,
               "AGENTIC_CI_CACHE_CONTRACT": json.dumps(contract),
               "AGENTIC_CI_TRUST_TIER": tier, "CI_REPO": "fixture/consumer",
               "QUERY_MODE": query, "POLICY_MODE": policy_mode,
               "ROOT": root, "REF": ref, "MARKER": str(marker),
               "SCANNED": str(scanned), "COPY_MODE": copy_mode,
               "QUERY_COUNTER": str(d / "query-counter")}
        p = subprocess.run([bash, "-euo", "pipefail", source, "nix", "publish",
                            *(roots if roots is not None else [root])],
                           env=env, text=True, capture_output=True)
        assert p.returncode == 0, (query, policy_mode, p.returncode, p.stderr)
        lines = p.stdout.splitlines()
        assert len(lines) == 1, (query, policy_mode, p.stdout)
        report = json.loads(lines[0])
        assert marker.exists() == copied, (tier, query, policy_mode, report)
        assert "SECRET" not in p.stdout + p.stderr, p
        assert report["trust_tier"] == tier
        if copied:
            args = marker.read_text().splitlines()
            assert root in args and ref in args, args
            assert "--closure-file" in scanned.read_text(), scanned.read_text()
            assert report["policy"]["identity"] == "fixture-policy"
            assert report["policy"]["revision"] == "fixture-revision"
            assert report["policy"]["outcome"] == "allowed"
            assert report["path_count"] == 2
            assert report["outcome"] == ("failed" if copy_mode == "fail" else "published")
        else:
            assert report["outcome"] in ("failed", "refused", "skipped-bound"), report
        count += 1
        print(f"ok {count}: {tier} query={query} policy={policy_mode} copied={copied}")
        return report

    for tier in ("protected", "pull-request"):
        run(tier, policy_mode="deny")
        run(tier, copied=True)
        run(tier, copied=True, copy_mode="fail")
        for mode in ("fail", "partial", "mixed", "nul", "cr", "empty", "missing-root", "malformed",
                     "subpath", "traversal", "unregistered", "incomplete", "drift"):
            run(tier, query=mode)
        run(tier, query="short", roots=[root, ref])
        for roots in ([], ["garbage"], [root + "/bin"], [root + "/../foo"]):
            run(tier, roots=roots)
        for mode in ("deny", "error", "other", "mutate"):
            run(tier, policy_mode=mode)
        run(tier, changes=lambda c: c["profiles"]["nix"].pop("publicationPolicy"))
        for bad in (None, {}, "shell command", {**policy, "version": 2},
                    {**policy, "argv": "eval me"}, {**policy, "argv": [1]},
                    {**policy, "argv": ["--closure-file", "/tmp/alternate"]},
                    {**policy, "argv": ["--closure-file=/tmp/alternate"]},
                    {**policy, "argv": ["--", root]},
                    {**policy, "argv": [root]},
                    {**policy, "argv": ["bad\u0000argument"]},
                    {**policy, "executable": "/tmp/policy"},
                    {**policy, "executable": root + "/missing"},
                    {**policy, "identity": "bad\nidentity"}):
            run(tier, changes=lambda c, b=bad: c["profiles"]["nix"].update(publicationPolicy=b))
        run(tier, changes=lambda c: c["profiles"]["nix"]["publicationPolicy"].update(executable=str(Path(bash).parent)))
        # Argument strings are passed verbatim, including shell metacharacters.
        injection = f"$(touch {d / 'injected'}); echo BAD"
        run(tier, copied=True, changes=lambda c: c["profiles"]["nix"]["publicationPolicy"]["argv"].append(injection))
        assert injection in scanned.read_text()
        assert not (d / "injected").exists()
        store.rename(bin_dir / "hidden-store")
        try:
            run(tier)
        finally:
            (bin_dir / "hidden-store").rename(store)
        # Producer no-work deliberately does not call writer.
        queue = []
        marker.unlink(missing_ok=True)
        if queue:
            run(tier, roots=queue)
        assert not marker.exists()
    print(f"PASS {count} offline writer controls; producer empty queues skipped explicitly")
