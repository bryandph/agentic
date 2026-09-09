# Scenario suite for agentic-ci-cache (run by checks.ci-cache-tools).
# Inputs from the derivation environment: tool, wrapped, contract, sccacheBin.
# Everything here is synthetic: fixture endpoints, fixture credentials, a
# throwaway Nix store under $TMPDIR, file-backed object stores.
set -euo pipefail

export HOME="$TMPDIR/home"
mkdir -p "$HOME"
export NIX_CONFIG="experimental-features = nix-command"
export CI_REPO="fixture/consumer"
export UV_PYTHON_DOWNLOADS=never UV_NO_CONFIG=1
export CARGO_HOME="$TMPDIR/cargo-home" CARGO_INCREMENTAL=0
export SCCACHE_SERVER_PORT=47226

run="$tool/bin/agentic-ci-cache"
obj="$TMPDIR/obj"
bc="$TMPDIR/binary-caches"
export AGENTIC_CI_CACHE_CONTRACT="$TMPDIR/contract.json"
jq --arg bc "$bc" '
  .profiles.nix.protectedWriteEndpoint = "file://\($bc)/protected"
  | .profiles.nix.pullRequestWriteEndpoint = "file://\($bc)/quarantine"
' "$contract" >"$AGENTIC_CI_CACHE_CONTRACT"

pass() { printf 'ok   %s\n' "$*"; }
fail() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}
expect() {
  # expect DESCRIPTION JSON JQ-PREDICATE
  jq -e "$3" <<<"$2" >/dev/null 2>&1 || {
    printf 'report: %s\n' "$2" >&2
    fail "$1"
  }
  pass "$1"
}
as_protected() { CI_PIPELINE_EVENT=push CI_COMMIT_BRANCH=main CI_REPO_DEFAULT_BRANCH=main "$@"; }
as_pull_request() { CI_PIPELINE_EVENT=pull_request CI_COMMIT_BRANCH=main CI_REPO_DEFAULT_BRANCH=main "$@"; }
as_branch() { CI_PIPELINE_EVENT=push CI_COMMIT_BRANCH=feature/x CI_REPO_DEFAULT_BRANCH=main "$@"; }

# --- delivery surfaces ------------------------------------------------------
echo "## delivery"
id="$(as_protected "$run" identity)"
expect "standalone tool resolves the runtime contract" "$id" '.repository == "fixture/consumer" and .trust_tier == "protected" and .nix.readEndpoints == ["https://nix-cache.fixture.example"]'
wrapped_id="$(env -u AGENTIC_CI_CACHE_CONTRACT CI_PIPELINE_EVENT=pull_request "$wrapped/bin/agentic-ci-cache" identity)"
expect "pre-wired tool carries the fixture contract" "$wrapped_id" '.trust_tier == "pull-request" and .nix.readEndpoints == ["https://nix-cache.fixture.example"]'
branch_id="$(as_branch "$run" identity)"
expect "a non-protected branch resolves to the pull-request tier" "$branch_id" '.trust_tier == "pull-request"'
if AGENTIC_CI_TRUST_TIER=admin "$run" identity >/dev/null 2>&1; then fail "invalid tier override accepted"; fi
if env -u AGENTIC_CI_CACHE_CONTRACT "$run" identity >/dev/null 2>&1; then fail "missing contract accepted"; fi
pass "usage errors exit non-zero"

# --- nix --------------------------------------------------------------------
echo "## nix"
cfg="$(as_pull_request "$run" nix config 2>/dev/null)"
grep -qx 'extra-substituters = https://nix-cache.fixture.example' <<<"$cfg" || fail "nix config lacks substituters"
grep -qx 'extra-trusted-public-keys = fixture-cache.example-1:PUBLIC-KEY-FIXTURE' <<<"$cfg" || fail "nix config lacks keys"
grep -q quarantine <<<"$cfg" && fail "quarantine leaked into substituter config"
pass "nix config emits signed substituters only"

export NIX_REMOTE="local?root=$TMPDIR/nixroot"
echo "fixture payload" >"$TMPDIR/payload"
path="$(nix store add --mode flat "$TMPDIR/payload" 2>/dev/null)"
hash="$(basename "$path" | cut -d- -f1)"
export CI_CACHE_PROTECTED_NIX_CACHE_TOKEN=fixture-token

r="$(as_protected "$run" nix publish "$path" 2>/dev/null)"
expect "protected closure lands in the protected cache" "$r" '.outcome == "published" and .trust_tier == "protected" and .path_count == 1 and (.backend | endswith("/protected"))'
[ -f "$bc/protected/$hash.narinfo" ] || fail "protected narinfo missing"
[ -e "$bc/quarantine" ] && fail "protected publication touched the quarantine"
pass "protected publication never writes the quarantine"

r="$((unset CI_CACHE_PROTECTED_NIX_CACHE_TOKEN; as_pull_request "$run" nix publish "$path") 2>/dev/null)"
expect "pull request publishes to the quarantine without protected credentials" "$r" '.outcome == "published" and .trust_tier == "pull-request" and (.backend | endswith("/quarantine"))'
[ -f "$bc/quarantine/$hash.narinfo" ] || fail "quarantine narinfo missing"
r="$(as_branch "$run" nix publish "$path" 2>/dev/null)"
expect "untrusted branch pushes use the quarantine tier" "$r" '.trust_tier == "pull-request" and (.backend | endswith("/quarantine"))'

r="$((unset CI_CACHE_PROTECTED_NIX_CACHE_TOKEN; as_protected "$run" nix publish "$path") 2>/dev/null)"
expect "protected file endpoint needs no token" "$r" '.outcome == "published"'
https_contract="$(jq -c '.profiles.nix.protectedWriteEndpoint = "https://nix-upload.fixture.example"' "$AGENTIC_CI_CACHE_CONTRACT")"
r="$((unset CI_CACHE_PROTECTED_NIX_CACHE_TOKEN; AGENTIC_CI_CACHE_CONTRACT="$https_contract" as_protected "$run" nix publish "$path") 2>/dev/null)"
expect "protected HTTPS endpoint without a token fails observably" "$r" '.outcome == "failed" and (.detail | contains("credential unavailable"))'
tmp_before="$(find "$TMPDIR" -maxdepth 1 -name 'tmp.*' | wc -l)"
r="$(AGENTIC_CI_CACHE_CONTRACT="$https_contract" as_protected "$run" nix publish "$path" 2>/dev/null)"
expect "unreachable protected backend with a token is a reported failure, not a build failure" "$r" '.outcome == "failed" and (.detail | contains("build result remains authoritative"))'
[ "$(find "$TMPDIR" -maxdepth 1 -name 'tmp.*' | wc -l)" -eq "$tmp_before" ] || fail "netrc temp file leaked"
pass "temporary netrc is removed"

s3_contract="$(jq -c '.profiles.nix.pullRequestWriteEndpoint = "s3://quarantine-fixture?endpoint=https://objects.fixture.example"' "$AGENTIC_CI_CACHE_CONTRACT")"
r="$(CI_CACHE_PROTECTED_AWS_ACCESS_KEY_ID=fx CI_CACHE_PROTECTED_AWS_SECRET_ACCESS_KEY=fx AGENTIC_CI_CACHE_CONTRACT="$s3_contract" as_pull_request "$run" nix publish "$path" 2>/dev/null)"
expect "pull request never borrows protected object credentials" "$r" '.outcome == "failed" and (.detail | contains("pull-request object credential unavailable"))'
r="$(CI_CACHE_PULL_REQUEST_AWS_ACCESS_KEY_ID=fx CI_CACHE_PULL_REQUEST_AWS_SECRET_ACCESS_KEY=fx AGENTIC_CI_CACHE_CONTRACT="$s3_contract" as_pull_request "$run" nix publish "$path" 2>/dev/null)"
expect "unreachable S3 quarantine is a reported failure" "$r" '.outcome == "failed" and (.detail | contains("status"))'
same_contract="$(jq -c '.profiles.nix.pullRequestWriteEndpoint = .profiles.nix.protectedWriteEndpoint' "$AGENTIC_CI_CACHE_CONTRACT")"
r="$(AGENTIC_CI_CACHE_CONTRACT="$same_contract" as_pull_request "$run" nix publish "$path" 2>/dev/null)"
expect "identical tier endpoints are refused" "$r" '.outcome == "refused"'
none_contract="$(jq -c 'del(.profiles.nix.pullRequestWriteEndpoint)' "$AGENTIC_CI_CACHE_CONTRACT")"
r="$(AGENTIC_CI_CACHE_CONTRACT="$none_contract" as_pull_request "$run" nix publish "$path" 2>/dev/null)"
expect "no quarantine configured disables pull-request publication" "$r" '.outcome == "skipped" and (.detail | contains("quarantine"))'
# Nix has no client-side identity key: a lock, toolchain, or architecture
# change yields a different store path, and publication is by path. Two
# payloads publish as two distinct narinfos; re-publishing a path is idempotent.
echo "fixture payload changed" >"$TMPDIR/payload2"
path2="$(nix store add --mode flat "$TMPDIR/payload2" 2>/dev/null)"
hash2="$(basename "$path2" | cut -d- -f1)"
[ "$hash2" != "$hash" ] || fail "changed content did not change the store path"
r="$(as_protected "$run" nix publish "$path2" 2>/dev/null)"
expect "changed input publishes as a distinct store path" "$r" '.outcome == "published" and .path_count == 1'
[ -f "$bc/protected/$hash2.narinfo" ] && [ -f "$bc/protected/$hash.narinfo" ] || fail "distinct narinfos missing"
r="$(as_protected "$run" nix publish "$path" 2>/dev/null)"
expect "re-publishing an already published path is idempotent" "$r" '.outcome == "published"'
[ "$(find "$bc/protected" -name '*.narinfo' | wc -l)" -eq 2 ] || fail "idempotent publish duplicated narinfos"
r="$(AGENTIC_NIX_PUBLISH_MAX_PATHS=0 as_protected "$run" nix publish "$path" 2>/dev/null)"
expect "closure above the bound is skipped" "$r" '.outcome == "skipped-bound" and .bound == 0'
r="$(as_protected "$run" nix publish /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nope 2>/dev/null)"
expect "invalid store path is reported" "$r" '.outcome == "failed" and .path_count == 0'
r="$(as_protected "$run" nix publish 2>/dev/null)"
expect "no paths is reported" "$r" '.outcome == "failed"'
broken_contract="$(jq -c '.profiles.nix.protectedWriteEndpoint = "file:///dev/null/nope"' "$AGENTIC_CI_CACHE_CONTRACT")"
r="$(AGENTIC_CI_CACHE_CONTRACT="$broken_contract" as_protected "$run" nix publish "$path" 2>/dev/null)"
expect "unwritable protected backend is a reported failure" "$r" '.outcome == "failed" and (.detail | contains("status 1"))'
unset NIX_REMOTE CI_CACHE_PROTECTED_NIX_CACHE_TOKEN

# --- sccache ------------------------------------------------------------------
echo "## sccache"
crate="$TMPDIR/crate"
mkdir -p "$crate/src" "$crate/.cargo"
printf '[package]\nname = "fixture"\nversion = "0.1.0"\nedition = "2021"\n' >"$crate/Cargo.toml"
# A library: sccache never caches `bin` crate types.
printf 'pub fn answer() -> u32 { 42 }\n' >"$crate/src/lib.rs"
printf '[build]\nrustc-wrapper = "sccache"\n' >"$crate/.cargo/config.toml"
cd "$crate"
gen=AGENTIC_SCCACHE_CACHE_GENERATION
stop_sccache() { PATH="$sccacheBin:$PATH" sccache --stop-server >/dev/null 2>&1 || true; }
trap stop_sccache EXIT
# `cargo clean` also probes rustc through the configured wrapper.
clean() { RUSTC_WRAPPER="" cargo clean -q; }

if cargo build --offline -q >"$TMPDIR/control" 2>&1; then fail "control: .cargo/config.toml wrapper is not in force"; fi
grep -q 'sccache' "$TMPDIR/control" || {
  cat "$TMPDIR/control" >&2
  fail "control build failed for a reason other than the missing wrapper"
}
pass "control: cargo honours the config-file wrapper (build fails without sccache)"

e="$(as_protected env "$gen=fx" "$run" sccache env 2>/dev/null)"
grep -qx 'SCCACHE_S3_KEY_PREFIX=ci/fixture/fixture/consumer/protected/[^/]*/[^/]*/fx/' <<<"$e" || fail "protected prefix shape: $e"
grep -qx 'SCCACHE_ENDPOINT=objects.fixture.example' <<<"$e" && grep -qx 'SCCACHE_S3_USE_SSL=true' <<<"$e" || fail "endpoint shape"
e2="$(as_pull_request env "$gen=fx" "$run" sccache env 2>/dev/null)"
grep -q '/pull-request/' <<<"$e2" || fail "pull-request prefix"
grep -qE 'fixture-(secret|token|value)' <<<"$e$e2" && fail "secret value in env output"
pass "sccache env is trust-tiered and secret-free"
e3="$(as_protected env "$gen=fy" "$run" sccache env 2>/dev/null)"
[ "$e" != "$e3" ] || fail "cache generation does not change the namespace"
pass "cache generation participates in the key"

# Toolchain and architecture identity come from `rustc -vV` on PATH. Each stub
# varies exactly one input against the real toolchain's baseline: the
# toolchain stub keeps the real host and changes release/commit; the
# architecture stub keeps the real release/commit and changes the host.
real_prefix="$(grep -o 'SCCACHE_S3_KEY_PREFIX=.*' <<<"$e" | cut -d= -f2-)"
real_vv="$(rustc -vV)"
real_host="$(awk '/^host:/ {print $2}' <<<"$real_vv")"
real_release="$(awk '/^release:/ {print $2}' <<<"$real_vv")"
real_hash="$(awk '/^commit-hash:/ {print $2}' <<<"$real_vv")"
real_compiler="$(awk -F/ '{print $7}' <<<"$real_prefix")"
[ "$real_compiler" = "${real_release}-${real_hash:0:9}" ] || fail "baseline compiler segment unexpected: $real_compiler"
stub_rustc() {
  # stub_rustc DIR HOST RELEASE HASH
  mkdir -p "$1"
  printf '#!/bin/sh\nprintf "rustc %s (%s 2026-01-01)\\nbinary: rustc\\ncommit-hash: %s\\ncommit-date: 2026-01-01\\nhost: %s\\nrelease: %s\\n"\n' "$3" "$4" "$4" "$2" "$3" >"$1/rustc"
  chmod +x "$1/rustc"
}
stub_rustc "$TMPDIR/rustc-other-toolchain" "$real_host" "1.0.0-fixture" "0123456789abcdef"
e4="$(PATH="$TMPDIR/rustc-other-toolchain:$PATH" as_protected env "$gen=fx" "$run" sccache env 2>/dev/null | grep -o 'SCCACHE_S3_KEY_PREFIX=.*' | cut -d= -f2-)"
[ "$e4" = "ci/fixture/fixture/consumer/protected/$real_host/1.0.0-fixture-012345678/fx/" ] || fail "toolchain-only change produced unexpected namespace: $e4"
[ "$e4" != "$real_prefix" ] || fail "toolchain change kept the namespace"
pass "toolchain-only change (same host, other rustc release/commit) selects a different namespace"
stub_rustc "$TMPDIR/rustc-other-arch" "fixture-other-arch-unknown-none" "$real_release" "$real_hash"
e5="$(PATH="$TMPDIR/rustc-other-arch:$PATH" as_protected env "$gen=fx" "$run" sccache env 2>/dev/null | grep -o 'SCCACHE_S3_KEY_PREFIX=.*' | cut -d= -f2-)"
[ "$e5" = "ci/fixture/fixture/consumer/protected/fixture-other-arch-unknown-none/$real_compiler/fx/" ] || fail "architecture-only change produced unexpected namespace: $e5"
[ "$e5" = "${real_prefix/$real_host/fixture-other-arch-unknown-none}" ] || fail "architecture change altered more than the host segment: $e5 vs $real_prefix"
pass "architecture-only change (same rustc release/commit, other host) selects a different namespace"

clean
as_pull_request env "$gen=fx" "$run" sccache run -- cargo build --offline -q 2>"$TMPDIR/err" || {
  cat "$TMPDIR/err" >&2
  fail "uncached fallback build failed"
}
expect "missing credentials degrade to an uncached build" "$(cat "$TMPDIR/err")" '.outcome == "failed" and (.detail | contains("credential unavailable"))'
[ -f target/debug/libfixture.rlib ] || fail "fallback build produced no artifact"
if as_pull_request env "$gen=fx" "$run" sccache run -- sh -c 'exit 17' 2>/dev/null; then fail "child failure swallowed"; fi
status=0
as_pull_request env "$gen=fx" "$run" sccache run -- sh -c 'exit 17' 2>/dev/null || status=$?
[ "$status" -eq 17 ] || fail "child exit status not propagated ($status)"
pass "child exit status propagates through the fallback"
child_env="$(CI_CACHE_PROTECTED_AWS_ACCESS_KEY_ID=fx AWS_ACCESS_KEY_ID=legacy as_pull_request env "$gen=fx" "$run" sccache run -- sh -c 'env | grep -cE "^(CI_CACHE_|AWS_|SCCACHE_(BUCKET|ENDPOINT|REGION|S3_|DIR)|RUSTC_WRAPPER=.)" || true; printf "[%s]\n" "${RUSTC_WRAPPER-unset}"' 2>/dev/null)"
[ "$child_env" = $'0\n[]' ] || fail "fallback child environment not scrubbed: $child_env"
pass "fallback child sees no tier variables and an empty RUSTC_WRAPPER"

export PATH="$sccacheBin:$PATH"
clean
AGENTIC_CI_CACHE_ENDPOINT=http://127.0.0.1:1 CI_CACHE_PULL_REQUEST_AWS_ACCESS_KEY_ID=fx CI_CACHE_PULL_REQUEST_AWS_SECRET_ACCESS_KEY=fx \
  as_pull_request "$run" sccache run -- cargo build --offline -q 2>"$TMPDIR/err" || fail "outage fallback build failed"
expect "unreachable backend degrades to an uncached build" "$(cat "$TMPDIR/err")" '.outcome == "failed" and (.detail | contains("startup failed"))'
status=0
AGENTIC_CI_CACHE_ENDPOINT=http://127.0.0.1:1 CI_CACHE_PULL_REQUEST_AWS_ACCESS_KEY_ID=fx CI_CACHE_PULL_REQUEST_AWS_SECRET_ACCESS_KEY=fx \
  as_pull_request "$run" sccache run -- sh -c 'exit 5' 2>/dev/null || status=$?
[ "$status" -eq 5 ] || fail "child exit status under outage not propagated ($status)"
pass "child exit status propagates under a backend outage"
r="$(CI_CACHE_PULL_REQUEST_AWS_ACCESS_KEY_ID=same CI_CACHE_PULL_REQUEST_AWS_SECRET_ACCESS_KEY=s CI_CACHE_PROTECTED_AWS_ACCESS_KEY_ID=same CI_CACHE_PROTECTED_AWS_SECRET_ACCESS_KEY=s as_pull_request "$run" sccache stats)"
expect "one credential mapped to both tiers is refused" "$r" '.outcome == "refused" and (.detail | contains("credential-shared-across-tiers"))'

export AGENTIC_CI_CACHE_ENDPOINT="file://$obj"
clean
as_pull_request "$run" sccache run -- cargo build --offline -q 2>"$TMPDIR/err" || fail "wrapped build failed"
expect "file backend: server ready, build wrapped" "$(cat "$TMPDIR/err")" '.outcome == "ready"'
r="$(as_pull_request "$run" sccache stats)"
expect "cold build: compile requests recorded, no hits" "$r" '.outcome == "reported" and .statistics.stats.compile_requests >= 1 and (.statistics.cache_location | contains("/pull-request/"))'
clean
as_pull_request "$run" sccache run -- cargo build --offline -q 2>"$TMPDIR/err" || fail "warm build failed"
r="$(as_pull_request "$run" sccache stats)"
expect "warm build: server reused, cache hits recorded" "$r" '([.statistics.stats.cache_hits.counts[]] | add) >= 1'
find "$obj/fixture-compiler-cache/ci/fixture/fixture/consumer/pull-request" -type f | grep -q . || fail "pull-request namespace empty on disk"
# The warm namespace belongs to the real toolchain only: another toolchain's
# namespace does not exist on the backend (a build with it would start cold).
e6="$(PATH="$TMPDIR/rustc-other-toolchain:$PATH" as_pull_request "$run" sccache env 2>/dev/null | grep -o 'SCCACHE_DIR=.*' | cut -d= -f2-)"
[ -n "$e6" ] && [ ! -e "$e6" ] || fail "other toolchain unexpectedly shares the warm namespace: $e6"
pass "warm sccache namespace is not shared with another toolchain (cold for it)"
clean
as_protected "$run" sccache run -- cargo build --offline -q 2>"$TMPDIR/err" || fail "protected build failed"
r="$(as_protected "$run" sccache stats)"
expect "protected tier: server replaced, separate namespace, cold" "$r" '(.statistics.cache_location | contains("/protected/")) and ([.statistics.stats.cache_hits.counts[]] | add // 0) == 0'
# Same repository, tier, compiler, and prefix, but a different backend on the
# same server port: the running server must not be reused.
clean
AGENTIC_CI_CACHE_ENDPOINT="file://$obj-second" as_protected "$run" sccache run -- cargo build --offline -q 2>"$TMPDIR/err" || fail "second-backend build failed"
r="$(AGENTIC_CI_CACHE_ENDPOINT="file://$obj-second" as_protected "$run" sccache stats)"
expect "changed backend with an identical prefix replaces the server" "$r" '(.statistics.cache_location | contains("'"$obj"'-second/")) and .statistics.stats.compile_requests >= 1'
# Healthy server on the port, then the backend switches to an unreachable
# endpoint: the tool must attempt a restart, fail closed on the cache, and
# still run the build uncached with the child's exit status.
clean
status=0
AGENTIC_CI_CACHE_ENDPOINT=http://127.0.0.1:1 CI_CACHE_PROTECTED_AWS_ACCESS_KEY_ID=fx CI_CACHE_PROTECTED_AWS_SECRET_ACCESS_KEY=fx \
  as_protected "$run" sccache run -- cargo build --offline -q 2>"$TMPDIR/err" || status=$?
[ "$status" -eq 0 ] || fail "outage after a healthy server broke the build ($status)"
expect "healthy server then unavailable backend on the same port falls back uncached" "$(cat "$TMPDIR/err")" '.outcome == "failed" and (.detail | contains("startup failed"))'
status=0
AGENTIC_CI_CACHE_ENDPOINT=http://127.0.0.1:1 CI_CACHE_PROTECTED_AWS_ACCESS_KEY_ID=fx CI_CACHE_PROTECTED_AWS_SECRET_ACCESS_KEY=fx \
  as_protected "$run" sccache run -- sh -c 'exit 9' 2>/dev/null || status=$?
[ "$status" -eq 9 ] || fail "child status after outage not propagated ($status)"
pass "child exit status propagates after a healthy-to-unavailable switch"
# The previous healthy backend can be resumed afterwards.
clean
as_protected "$run" sccache run -- cargo build --offline -q 2>"$TMPDIR/err" || fail "resume build failed"
expect "healthy backend resumes wrapped after the outage" "$(cat "$TMPDIR/err")" '.outcome == "ready"'
stop_sccache
unset AGENTIC_CI_CACHE_ENDPOINT
cd "$TMPDIR"

# --- uv -----------------------------------------------------------------------
echo "## uv"
ws="$TMPDIR/workspace"
mkdir -p "$ws"
cd "$ws"
export AGENTIC_CI_CACHE_ENDPOINT="file://$obj"
r="$(as_protected "$run" uv restore)"
expect "missing lock input leaves the identity incomplete" "$r" '.outcome == "skipped" and (.detail | contains("lock input"))'
echo "lock-v1" >uv.lock
eval "$(as_protected "$run" uv env 2>/dev/null)"
export UV_CACHE_DIR
[ "$UV_CACHE_DIR" = "$ws/.ci-cache/uv" ] || fail "UV_CACHE_DIR: $UV_CACHE_DIR"
pass "uv env points at the workspace-local cache directory"

r="$(as_protected "$run" uv restore)"
expect "cold restore is a miss" "$r" '.outcome == "miss" and (.identity.key | test("^ci/fixture/fixture/consumer/protected/uv/[^/]+/cpython-[^/]+/[^/]+/[0-9a-f]{64}\\.tar\\.zst$"))'
key_v1="$(jq -r .identity.key <<<"$r")"
mkdir -p "$UV_CACHE_DIR/sdists-v9/pkg" "$UV_CACHE_DIR/wheels-v5/pkg" "$UV_CACHE_DIR/archive-v0/x"
echo sdist >"$UV_CACHE_DIR/sdists-v9/pkg/pkg.tar.gz"
echo wheel >"$UV_CACHE_DIR/wheels-v5/pkg/pkg.whl"
echo arch >"$UV_CACHE_DIR/archive-v0/x/f"
ln -s ../../archive-v0/x "$UV_CACHE_DIR/sdists-v9/pkg/link"
r="$(as_protected "$run" uv publish 2>/dev/null)"
expect "publish prunes then uploads under the protected key" "$r" '.outcome == "published" and .bytes > 0 and .identity.key == "'"$key_v1"'"'
[ -f "$obj/fixture-python-cache/$key_v1" ] || fail "archive missing on backend"
[ ! -e "$UV_CACHE_DIR/wheels-v5/pkg/pkg.whl" ] || fail "uv cache prune --ci did not run"
pass "pre-built wheel removed by CI pruning"
r="$(as_protected "$run" uv publish 2>/dev/null)"
expect "warm publish is skipped, keys are immutable" "$r" '.outcome == "skipped-exists"'

rm -rf "$UV_CACHE_DIR"
r="$(as_protected "$run" uv restore)"
expect "warm restore hits the exact key" "$r" '.outcome == "restored" and .source_tier == "protected" and .bytes > 0'
[ -f "$UV_CACHE_DIR/sdists-v9/pkg/pkg.tar.gz" ] && [ -L "$UV_CACHE_DIR/sdists-v9/pkg/link" ] || fail "restored content incomplete"
find "$ws/.ci-cache" -mindepth 1 -maxdepth 1 ! -name uv | grep -q . && fail "restore left staging debris"
pass "restore populates only the cache directory"
r="$(as_protected "$run" uv restore)"
expect "restore into a populated cache directory is skipped" "$r" '.outcome == "skipped" and (.detail | contains("already populated"))'

rm -rf "$UV_CACHE_DIR"
r="$(as_pull_request "$run" uv restore)"
expect "pull request restores the protected baseline" "$r" '.outcome == "restored" and .trust_tier == "pull-request" and .source_tier == "protected"'
r="$(as_pull_request "$run" uv publish 2>/dev/null)"
expect "pull request publishes into its own namespace" "$r" '.outcome == "published" and (.identity.key | contains("/pull-request/"))'
key_pr="$(jq -r .identity.key <<<"$r")"

rm -rf "$UV_CACHE_DIR"
echo "lock-v2" >uv.lock
r="$(as_protected "$run" uv restore)"
expect "lock change invalidates the exact key" "$r" '.outcome == "miss"'
r="$(AGENTIC_UV_CACHE_GENERATION=other as_protected "$run" uv restore)"
expect "uv generation change invalidates the exact key" "$r" '.outcome == "miss" and (.identity.key | contains("/other/"))'
# Python ABI is queried from the interpreter in use: with the real python
# off PATH, a stub python3 reporting another ABI (reached through the
# helper's PATH fallback) must change the key and miss.
echo "lock-v1" >uv.lock
mkdir -p "$TMPDIR/py-other"
printf '#!/bin/sh\necho cpython-000-fixture-other-abi\n' >"$TMPDIR/py-other/python3"
chmod +x "$TMPDIR/py-other/python3"
real_py_dir="$(dirname "$(command -v python3)")"
path_without_py="$(tr ':' '\n' <<<"$PATH" | grep -vxF "$real_py_dir" | paste -sd: -)"
r="$(PATH="$TMPDIR/py-other:$path_without_py" as_protected "$run" uv restore)"
expect "python ABI change invalidates the exact key" "$r" '.outcome == "miss" and (.identity.python_abi == "cpython-000-fixture-other-abi") and (.identity.key | contains("/cpython-000-fixture-other-abi/"))'
echo "lock-v1" >uv.lock
rm -f "$obj/fixture-python-cache/$key_v1"
rm -rf "$UV_CACHE_DIR"
r="$(as_protected "$run" uv restore)"
expect "protected never reads a pull-request-only entry" "$r" '.outcome == "miss"'
[ -f "$obj/fixture-python-cache/$key_pr" ] || fail "pull-request entry vanished"
mkdir -p "$UV_CACHE_DIR/sdists-v9/pkg"
echo sdist >"$UV_CACHE_DIR/sdists-v9/pkg/pkg.tar.gz"
r="$(AGENTIC_UV_PUBLISH_MAX_BYTES=1 as_protected "$run" uv publish 2>/dev/null)"
expect "oversized cache is not published" "$r" '.outcome == "skipped-bound"'
r="$(AGENTIC_CI_CACHE_ENDPOINT=file:///dev/null/nope as_protected "$run" uv publish 2>/dev/null)"
expect "unwritable backend is a reported failure" "$r" '.outcome == "failed" and (.detail | contains("upload failed"))'
r="$((unset AGENTIC_CI_CACHE_ENDPOINT; CI_CACHE_PROTECTED_AWS_ACCESS_KEY_ID=fx CI_CACHE_PROTECTED_AWS_SECRET_ACCESS_KEY=fx as_protected "$run" uv publish) 2>/dev/null)"
expect "unreachable S3 backend is a reported failure" "$r" '.outcome == "failed" and (.detail | contains("object backend error"))'
r="$((unset AGENTIC_CI_CACHE_ENDPOINT; as_protected "$run" uv publish) 2>/dev/null)"
expect "S3 without tier credentials is a reported failure" "$r" '.outcome == "failed" and (.detail | contains("credential unavailable"))'
r="$((unset AGENTIC_CI_CACHE_ENDPOINT; CI_CACHE_PROTECTED_AWS_ACCESS_KEY_ID=same CI_CACHE_PROTECTED_AWS_SECRET_ACCESS_KEY=s CI_CACHE_PULL_REQUEST_AWS_ACCESS_KEY_ID=same CI_CACHE_PULL_REQUEST_AWS_SECRET_ACCESS_KEY=s as_protected "$run" uv publish) 2>/dev/null)"
expect "shared credential across tiers is refused" "$r" '.outcome == "refused"'

# Hostile archives on the backend must never reach the workspace.
target="$obj/fixture-python-cache/$key_v1"
mkdir -p "$(dirname "$target")"
evil="$TMPDIR/evil"
craft() {
  rm -rf "$evil"
  mkdir -p "$evil"
  (cd "$evil" && "$@")
}
craft sh -c 'mkdir sub && echo evil > sub/f && tar --zstd -cf "$0" --transform "s#^sub/f#../escaped#" sub/f' "$target"
rm -rf "$UV_CACHE_DIR"
r="$(as_protected "$run" uv restore)"
expect "path traversal member is rejected" "$r" '.outcome == "failed" and (.detail | contains("escapes"))'
[ ! -e "$ws/.ci-cache/escaped" ] && [ ! -e "$ws/escaped" ] || fail "traversal escaped"
craft sh -c 'ln -s /etc/passwd bad && tar --zstd -cf "$0" bad' "$target"
r="$(as_protected "$run" uv restore)"
expect "absolute symlink target is rejected" "$r" '.outcome == "failed" and (.detail | contains("escapes"))'
craft sh -c 'mkdir d && ln -s ../../outside d/bad && tar --zstd -cf "$0" d' "$target"
r="$(as_protected "$run" uv restore)"
expect "relative symlink escaping the root is rejected" "$r" '.outcome == "failed" and (.detail | contains("escapes"))'
craft sh -c 'head -c 4096 /dev/zero > big && tar --zstd -cf "$0" big' "$target"
r="$(AGENTIC_UV_RESTORE_MAX_BYTES=1024 as_protected "$run" uv restore)"
expect "archive above the restore bound is rejected" "$r" '.outcome == "failed" and (.detail | contains("restore bound"))'
echo "not an archive" >"$target"
r="$(as_protected "$run" uv restore)"
expect "corrupt archive is rejected" "$r" '.outcome == "failed" and (.detail | contains("not a readable"))'
[ ! -e "$UV_CACHE_DIR" ] || fail "rejected restore left a cache directory"
find "$ws/.ci-cache" -mindepth 1 -maxdepth 1 2>/dev/null | grep -q . && fail "rejected restore left staging debris"
pass "rejected archives leave the workspace untouched"

echo "all scenarios passed"
