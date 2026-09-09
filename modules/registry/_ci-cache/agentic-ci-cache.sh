# agentic-ci-cache: consumer-side implementation of the agentic CI cache
# contract (modules/registry/_ci-cache.nix). Wrapped by writeShellApplication
# (bash, `set -euo pipefail`, shellcheck-clean).
#
# Every cache action is an optimisation: restore/publish/stats subcommands
# always exit 0 and emit one structured JSON report line on stdout so the
# consuming workflow can surface failures without changing its build result.
# Only usage errors (no contract, malformed tier) exit non-zero.
#
# Secrets are read exclusively from trust-tier-prefixed variables and are
# never printed; a workflow mounts only its own tier's credentials.

CONTRACT=""
REPOSITORY=""
TRUST_TIER=""
STARTED="$(date +%s)"
REPORT_FD=1

die() {
  printf 'agentic-ci-cache: %s\n' "$*" >&2
  exit 2
}

usage() {
  cat >&2 <<'USAGE'
usage: agentic-ci-cache <subcommand>

  identity                      resolved repository, trust tier, and per-profile key inputs
  nix config                    nix.conf lines (extra-substituters, extra-trusted-public-keys)
  nix publish <store-path>...   trust-tiered completed-closure publication
  sccache env                   non-secret SCCACHE_* configuration lines
  sccache run -- <command>...   run a command with tiered sccache configuration and credentials
  sccache stats                 report `sccache --show-stats` as JSON
  uv env                        UV_CACHE_DIR assignment for the workspace-local uv cache
  uv restore                    exact-key restore of the uv cache (pull requests may read the protected baseline)
  uv publish                    `uv cache prune --ci` then bounded publication under the tier key

Environment: AGENTIC_CI_CACHE_CONTRACT (contract JSON path or inline JSON),
CI_REPO / AGENTIC_CI_REPOSITORY, CI_PIPELINE_EVENT + CI_COMMIT_BRANCH +
CI_REPO_DEFAULT_BRANCH or AGENTIC_CI_TRUST_TIER, and tier-prefixed credentials
CI_CACHE_PROTECTED_<NAME>[_FILE] / CI_CACHE_PULL_REQUEST_<NAME>[_FILE].
USAGE
  exit 2
}

# --- contract ---------------------------------------------------------------

load_contract() {
  local src="${AGENTIC_CI_CACHE_CONTRACT:-}"
  [ -n "$src" ] || die "AGENTIC_CI_CACHE_CONTRACT is not set (path to the contract JSON, or inline JSON)"
  case "$src" in
    '{'*) CONTRACT="$src" ;;
    *)
      [ -r "$src" ] || die "contract '$src' is not readable"
      CONTRACT="$(cat -- "$src")"
      ;;
  esac
  jq -e '.version == 1 and (.profiles | type == "object")' <<<"$CONTRACT" >/dev/null 2>&1 \
    || die "contract is not a version-1 agentic CI cache contract"
}

profile_json() {
  jq -c --arg p "$1" '.profiles[$p] // empty' <<<"$CONTRACT"
}

pget() {
  # pget PROFILE_JSON JQ_FILTER -> raw value ("" for null)
  jq -r "$2 // empty" <<<"$1"
}

# --- identity -----------------------------------------------------------------

resolve_trust_tier() {
  local override="${AGENTIC_CI_TRUST_TIER:-}"
  if [ -n "$override" ]; then
    case "$override" in
      protected | pull-request) TRUST_TIER="$override" ;;
      *) die "AGENTIC_CI_TRUST_TIER must be 'protected' or 'pull-request'" ;;
    esac
    return
  fi
  local event="${CI_PIPELINE_EVENT:-}" branch="${CI_COMMIT_BRANCH:-}" default="${CI_REPO_DEFAULT_BRANCH:-main}"
  # Woodpecker reports the base branch for pull requests, so the event check
  # must come first: a pull request against main is never protected.
  if [ "$event" = pull_request ]; then
    TRUST_TIER=pull-request
  elif [ -n "$branch" ] && { [ "$branch" = "$default" ] || [[ "$branch" == release/* ]]; }; then
    TRUST_TIER=protected
  else
    TRUST_TIER=pull-request
  fi
}

other_tier() {
  case "$1" in
    protected) echo pull-request ;;
    pull-request) echo protected ;;
  esac
}

tier_prefix() {
  case "$1" in
    protected) echo CI_CACHE_PROTECTED_ ;;
    pull-request) echo CI_CACHE_PULL_REQUEST_ ;;
  esac
}

resolve_repository() {
  REPOSITORY="${AGENTIC_CI_REPOSITORY:-${CI_REPO:-}}"
  [ -n "$REPOSITORY" ] || die "repository identity unavailable: set CI_REPO or AGENTIC_CI_REPOSITORY"
  REPOSITORY="$(printf '%s' "$REPOSITORY" | tr -c 'A-Za-z0-9._/-' '_' | sed -e 's#^/*##' -e 's#/*$##' -e 's#//*#/#g')"
  [ -n "$REPOSITORY" ] || die "repository identity is empty after sanitising"
}

sanitize_segment() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

platform_id() {
  printf '%s-%s' "$(uname -s | tr '[:upper:]' '[:lower:]')" "$(uname -m)"
}

# --- secrets ------------------------------------------------------------------
# Values are only ever captured into shell variables handed to the client
# tool; nothing here writes a value to stdout/stderr of the tool itself.

secret_value() {
  # secret_value TIER NAME -> value on stdout; 1 when unavailable.
  local prefix var file
  prefix="$(tier_prefix "$1")"
  var="${prefix}$2"
  file="${var}_FILE"
  if [ -n "${!file:-}" ]; then
    [ -s "${!file}" ] || return 1
    cat -- "${!file}"
    return 0
  fi
  if [ -n "${!var:-}" ]; then
    printf '%s' "${!var}"
    return 0
  fi
  return 1
}

secret_present() {
  secret_value "$1" "$2" >/dev/null 2>&1
}

secret_fingerprint() {
  local v
  if v="$(secret_value "$1" "$2")"; then
    printf '%s' "$v" | sha256sum | cut -d' ' -f1
  fi
}

SPLIT_DETAIL=""
credential_split_ok() {
  # credential_split_ok NAME... -> 1 (and SPLIT_DETAIL) when a value is shared
  # by both tiers. Only one tier is ever required; this catches a legacy
  # single credential mapped to both prefixed names.
  local name
  for name in "$@"; do
    if secret_present protected "$name" && secret_present pull-request "$name"; then
      if [ "$(secret_fingerprint protected "$name")" = "$(secret_fingerprint pull-request "$name")" ]; then
        SPLIT_DETAIL="credential-shared-across-tiers: $name carries the same value for the protected and pull-request tiers"
        return 1
      fi
    fi
  done
  return 0
}

MISSING_SECRETS=()
export_tier_secrets() {
  # export_tier_secrets NAME... -> exports NAME=value from the current tier's
  # prefixed variables; 1 when any is unavailable (MISSING_SECRETS lists them).
  local name value
  MISSING_SECRETS=()
  for name in "$@"; do
    if value="$(secret_value "$TRUST_TIER" "$name")"; then
      export "$name=$value"
    else
      MISSING_SECRETS+=("$name")
    fi
  done
  [ "${#MISSING_SECRETS[@]}" -eq 0 ]
}

scrub_tier_env() {
  # Child processes never see any tier-prefixed variable. (`env -0` rather
  # than compgen: nixpkgs' non-interactive bash ships without progcomp.)
  local kv name
  while IFS= read -r -d '' kv; do
    name="${kv%%=*}"
    case "$name" in
      CI_CACHE_PROTECTED_* | CI_CACHE_PULL_REQUEST_*) unset "$name" ;;
    esac
  done < <(env -0)
}

# --- reporting ----------------------------------------------------------------

report() {
  # report REPORT COMPONENT BACKEND OUTCOME DETAIL [EXTRA_JSON]
  local extra="${6:-{\}}"
  jq -nc \
    --arg report "$1" \
    --arg component "$2" \
    --arg repository "$REPOSITORY" \
    --arg trust_tier "$TRUST_TIER" \
    --arg backend "$3" \
    --arg outcome "$4" \
    --arg detail "$5" \
    --argjson duration "$(($(date +%s) - STARTED))" \
    --argjson extra "$extra" \
    '{report: $report, component: $component, repository: $repository, trust_tier: $trust_tier, backend: $backend, outcome: $outcome, detail: $detail, duration_seconds: $duration} + $extra' \
    >&"$REPORT_FD"
}

# --- object store (uv transport) ----------------------------------------------

OBJ_SCHEME=""
OBJ_ROOT=""
OBJ_ENDPOINT=""
OBJ_REGION=""
OBJ_LABEL=""

object_backend() {
  # object_backend PROFILE_JSON
  local endpoint bucket
  endpoint="${AGENTIC_CI_CACHE_ENDPOINT:-$(pget "$1" .endpoint)}"
  bucket="$(pget "$1" .bucket)"
  OBJ_REGION="$(pget "$1" .region)"
  [ -n "$endpoint" ] && [ -n "$bucket" ] || die "profile lacks an object endpoint or bucket"
  case "$endpoint" in
    file://*)
      OBJ_SCHEME="file"
      OBJ_ROOT="${endpoint#file://}/$bucket"
      OBJ_ENDPOINT=""
      ;;
    *)
      OBJ_SCHEME="s3"
      OBJ_ROOT="s3://$bucket"
      OBJ_ENDPOINT="$endpoint"
      ;;
  esac
  OBJ_LABEL="$endpoint/$bucket"
}

s5() {
  AWS_REGION="$OBJ_REGION" s5cmd --endpoint-url "$OBJ_ENDPOINT" "$@"
}

OBJ_ERROR=""
obj_exists() {
  # obj_exists KEY -> 0 present, 1 absent, 2 backend failure (OBJ_ERROR)
  local err
  if [ "$OBJ_SCHEME" = file ]; then
    [ -f "$OBJ_ROOT/$1" ] && return 0
    return 1
  fi
  err="$(s5 ls "$OBJ_ROOT/$1" 2>&1 >/dev/null)" && return 0
  if grep -qi 'no object found' <<<"$err"; then
    return 1
  fi
  OBJ_ERROR="$(tail -n 1 <<<"$err")"
  return 2
}

obj_get() {
  # obj_get KEY DEST
  if [ "$OBJ_SCHEME" = file ]; then
    cp -- "$OBJ_ROOT/$1" "$2"
  else
    s5 cp "$OBJ_ROOT/$1" "$2" >/dev/null
  fi
}

obj_put() {
  # obj_put SRC KEY
  if [ "$OBJ_SCHEME" = file ]; then
    mkdir -p -- "$(dirname -- "$OBJ_ROOT/$2")"
    cp -- "$1" "$OBJ_ROOT/$2"
  else
    s5 cp "$1" "$OBJ_ROOT/$2" >/dev/null
  fi
}

CRED_DETAIL=""
object_credentials_ready() {
  # object_credentials_ready PROFILE_JSON -> 0 ready; 1 refused (split);
  # 2 missing. Sets CRED_DETAIL. Must run in the main shell: it exports the
  # resolved credentials for the client tool.
  local names=()
  CRED_DETAIL=""
  [ "$OBJ_SCHEME" = file ] && return 0
  mapfile -t names < <(jq -r '.runtimeSecretEnv[]?' <<<"$1")
  if ! credential_split_ok "${names[@]}"; then
    CRED_DETAIL="$SPLIT_DETAIL"
    return 1
  fi
  if ! export_tier_secrets "${names[@]}"; then
    CRED_DETAIL="$TRUST_TIER credential unavailable: ${MISSING_SECRETS[*]} (expected $(tier_prefix "$TRUST_TIER")<NAME> or <NAME>_FILE)"
    return 2
  fi
  return 0
}

# --- nix ----------------------------------------------------------------------

nix_config() {
  local profile
  REPORT_FD=2
  profile="$(profile_json nix)"
  if [ -z "$profile" ]; then
    report substitution-summary nix-cache-configuration none skipped "nix profile is not part of the contract"
    return 0
  fi
  # The quarantine endpoint is deliberately never a substituter: the lane
  # store is shared, so unsigned pull-request outputs must not enter it.
  printf 'extra-substituters = %s\n' "$(jq -r '.readEndpoints | join(" ")' <<<"$profile")"
  printf 'extra-trusted-public-keys = %s\n' "$(jq -r '.trustedPublicKeys | join(" ")' <<<"$profile")"
}

nix_url_host() {
  local rest="${1#*://}"
  rest="${rest%%/*}"
  rest="${rest%%\?*}"
  rest="${rest#*@}"
  printf '%s' "${rest%%:*}"
}

NETRC=""
cleanup_netrc() {
  [ -n "$NETRC" ] && rm -f -- "$NETRC"
  return 0
}

nix_publish() {
  local profile target other_target scheme paths=() max copy_status=0 detail
  local -a nix_opts=()
  profile="$(profile_json nix)"
  if [ -z "$profile" ]; then
    report publication-result nix-cache-publication none skipped "nix profile is not part of the contract"
    return 0
  fi
  if [ "$#" -eq 0 ]; then
    report publication-result nix-cache-publication none failed "no completed output paths were supplied"
    return 0
  fi

  if [ "$TRUST_TIER" = protected ]; then
    target="$(pget "$profile" .protectedWriteEndpoint)"
    other_target="$(pget "$profile" .pullRequestWriteEndpoint)"
    [ -n "$target" ] || {
      report publication-result nix-cache-publication none skipped "no protected write endpoint is configured"
      return 0
    }
  else
    target="$(pget "$profile" .pullRequestWriteEndpoint)"
    other_target="$(pget "$profile" .protectedWriteEndpoint)"
    [ -n "$target" ] || {
      report publication-result nix-cache-publication none skipped "pull-request quarantine endpoint is not configured; pull-request Nix publication stays disabled until a quarantine target exists"
      return 0
    }
  fi
  if [ -n "$other_target" ] && [ "$target" = "$other_target" ]; then
    report publication-result nix-cache-publication "$target" refused "protected and pull-request write endpoints are identical; trust tiers must not share a Nix publication target"
    return 0
  fi

  scheme="${target%%://*}"
  trap cleanup_netrc EXIT

  case "$scheme" in
    http | https)
      local prefix netrc_file token login
      prefix="$(tier_prefix "$TRUST_TIER")"
      netrc_file="${prefix}NIX_NETRC_FILE"
      if [ -n "${!netrc_file:-}" ] && [ -s "${!netrc_file}" ]; then
        nix_opts+=(--option netrc-file "${!netrc_file}")
      elif token="$(secret_value "$TRUST_TIER" NIX_CACHE_TOKEN)"; then
        if ! credential_split_ok NIX_CACHE_TOKEN; then
          report publication-result nix-cache-publication "$target" refused "$SPLIT_DETAIL"
          return 0
        fi
        login="${prefix}NIX_CACHE_LOGIN"
        NETRC="$(mktemp)"
        chmod 600 "$NETRC"
        printf 'machine %s login %s password %s\n' "$(nix_url_host "$target")" "${!login:-ci}" "$token" >"$NETRC"
        nix_opts+=(--option netrc-file "$NETRC")
      else
        report publication-result nix-cache-publication "$target" failed "$TRUST_TIER cache credential unavailable (expected ${prefix}NIX_NETRC_FILE or ${prefix}NIX_CACHE_TOKEN[_FILE])"
        return 0
      fi
      ;;
    s3)
      if ! credential_split_ok AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; then
        report publication-result nix-cache-publication "$target" refused "$SPLIT_DETAIL"
        return 0
      fi
      if ! export_tier_secrets AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; then
        report publication-result nix-cache-publication "$target" failed "$TRUST_TIER object credential unavailable: ${MISSING_SECRETS[*]}"
        return 0
      fi
      if secret_present "$TRUST_TIER" AWS_SESSION_TOKEN; then
        export_tier_secrets AWS_SESSION_TOKEN || true
      fi
      ;;
    file) ;;
    *)
      report publication-result nix-cache-publication "$target" failed "unsupported publication endpoint scheme '$scheme'"
      return 0
      ;;
  esac
  scrub_tier_env

  # Bounded: the closure of the supplied outputs, computed locally. No
  # cache-status walk against the backend.
  if ! mapfile -t paths < <(nix path-info -r "$@" 2>/dev/null); then
    paths=()
  fi
  if [ "${#paths[@]}" -eq 0 ]; then
    report publication-result nix-cache-publication "$target" failed "supplied paths are not valid in the local store" '{"path_count": 0}'
    return 0
  fi
  max="${AGENTIC_NIX_PUBLISH_MAX_PATHS:-2000}"
  if [ "${#paths[@]}" -gt "$max" ]; then
    report publication-result nix-cache-publication "$target" skipped-bound "closure of ${#paths[@]} paths exceeds the publication bound of $max" "{\"path_count\": ${#paths[@]}, \"bound\": $max}"
    return 0
  fi

  if nix copy --to "$target" "${nix_opts[@]}" "$@" 2>&1 | sed 's/^/agentic-ci-cache: nix copy: /' >&2; then
    copy_status=0
  else
    copy_status="${PIPESTATUS[0]}"
  fi
  if [ "$copy_status" -eq 0 ]; then
    report publication-result nix-cache-publication "$target" published "completed closure publication succeeded; promotion between tiers is rebuild-based" "{\"path_count\": ${#paths[@]}}"
  else
    detail="closure publication failed with status $copy_status; build result remains authoritative"
    report publication-result nix-cache-publication "$target" failed "$detail" "{\"path_count\": ${#paths[@]}}"
  fi
}

# --- sccache ------------------------------------------------------------------

SCC_HOST=""
SCC_COMPILER=""
SCC_GEN=""
SCC_PREFIX=""
SCC_DETAIL=""

sccache_identity() {
  # sccache_identity PROFILE_JSON -> 0 or 1 with SCC_DETAIL
  local vv release hash key_prefix
  if ! command -v rustc >/dev/null 2>&1; then
    SCC_DETAIL="rustc is not on PATH; compiler generation cannot be resolved"
    return 1
  fi
  vv="$(rustc -vV 2>/dev/null)" || {
    SCC_DETAIL="rustc -vV failed"
    return 1
  }
  SCC_HOST="$(awk '/^host:/ {print $2}' <<<"$vv")"
  release="$(awk '/^release:/ {print $2}' <<<"$vv")"
  hash="$(awk '/^commit-hash:/ {print substr($2, 1, 9)}' <<<"$vv")"
  [ -n "$SCC_HOST" ] && [ -n "$release" ] || {
    SCC_DETAIL="rustc -vV output lacks host/release"
    return 1
  }
  SCC_COMPILER="$(sanitize_segment "${release}${hash:+-$hash}")"
  if [ -n "${AGENTIC_SCCACHE_CACHE_GENERATION:-}" ]; then
    SCC_GEN="$(sanitize_segment "$AGENTIC_SCCACHE_CACHE_GENERATION")"
  elif command -v sccache >/dev/null 2>&1; then
    SCC_GEN="$(sanitize_segment "$(sccache --version 2>/dev/null | awk '{print $2}')")"
  else
    SCC_DETAIL="sccache is not on PATH and AGENTIC_SCCACHE_CACHE_GENERATION is unset"
    return 1
  fi
  key_prefix="$(pget "$1" .keyPrefix)"
  SCC_PREFIX="${key_prefix:-ci}/$REPOSITORY/$TRUST_TIER/$SCC_HOST/$SCC_COMPILER/$SCC_GEN/"
}

sccache_identity_json() {
  jq -nc --arg host "$SCC_HOST" --arg compiler "$SCC_COMPILER" --arg gen "$SCC_GEN" --arg prefix "$SCC_PREFIX" \
    '{identity: {architecture: $host, compiler_generation: $compiler, cache_generation: $gen, key_prefix: $prefix}}'
}

sccache_env_lines() {
  # sccache_env_lines PROFILE_JSON (object_backend + sccache_identity done)
  local host_port use_ssl=false
  if [ "$OBJ_SCHEME" = file ]; then
    printf 'SCCACHE_DIR=%s\n' "$OBJ_ROOT/$SCC_PREFIX"
  else
    case "$OBJ_ENDPOINT" in https://*) use_ssl=true ;; esac
    host_port="${OBJ_ENDPOINT#*://}"
    host_port="${host_port%%/*}"
    printf 'SCCACHE_BUCKET=%s\n' "$(pget "$1" .bucket)"
    printf 'SCCACHE_ENDPOINT=%s\n' "$host_port"
    printf 'SCCACHE_REGION=%s\n' "$OBJ_REGION"
    printf 'SCCACHE_S3_USE_SSL=%s\n' "$use_ssl"
    printf 'SCCACHE_S3_KEY_PREFIX=%s\n' "$SCC_PREFIX"
  fi
  printf 'RUSTC_WRAPPER=sccache\n'
}

sccache_apply_env() {
  local line
  while IFS= read -r line; do
    export "${line?}"
  done < <(sccache_env_lines "$1")
}

sccache_env() {
  local profile
  REPORT_FD=2
  profile="$(profile_json rust)"
  if [ -z "$profile" ]; then
    report sccache-environment sccache-environment none skipped "rust profile is not part of the contract"
    return 0
  fi
  object_backend "$profile"
  if ! sccache_identity "$profile"; then
    report sccache-environment sccache-environment "$OBJ_LABEL" failed "$SCC_DETAIL"
    return 0
  fi
  sccache_env_lines "$profile"
  report sccache-environment sccache-environment "$OBJ_LABEL" resolved "trust-tiered sccache namespace resolved" "$(sccache_identity_json)"
}

sccache_prepare() {
  # sccache_prepare -> 0 when env + credentials are exported; 1 after a report
  local profile
  profile="$(profile_json rust)"
  if [ -z "$profile" ]; then
    report sccache-statistics sccache none skipped "rust profile is not part of the contract"
    return 1
  fi
  object_backend "$profile"
  if ! sccache_identity "$profile"; then
    report sccache-statistics sccache "$OBJ_LABEL" failed "$SCC_DETAIL"
    return 1
  fi
  local cred=0
  object_credentials_ready "$profile" || cred=$?
  case "$cred" in
    0) ;;
    1)
      report sccache-statistics sccache "$OBJ_LABEL" refused "$CRED_DETAIL" "$(sccache_identity_json)"
      return 1
      ;;
    *)
      report sccache-statistics sccache "$OBJ_LABEL" failed "$CRED_DETAIL" "$(sccache_identity_json)"
      return 1
      ;;
  esac
  sccache_apply_env "$profile"
  scrub_tier_env
  return 0
}

sccache_uncached() {
  # Uncached fallback. The child never sees tier-prefixed variables, any
  # partially exported backend credential, or the sccache configuration.
  # Cargo also reads build.rustc-wrapper from .cargo/config.toml; only an
  # exported EMPTY RUSTC_WRAPPER overrides that, an unset one does not.
  local profile name
  scrub_tier_env
  profile="$(profile_json rust)"
  if [ -n "$profile" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] && unset "$name"
    done < <(jq -r '.runtimeSecretEnv[]?' <<<"$profile")
  fi
  unset AWS_SESSION_TOKEN
  unset SCCACHE_BUCKET SCCACHE_ENDPOINT SCCACHE_REGION SCCACHE_S3_USE_SSL SCCACHE_S3_KEY_PREFIX SCCACHE_DIR
  export RUSTC_WRAPPER=""
}

sccache_server_location() {
  # Cache location of an already-running server, without starting one.
  # (`sccache --show-stats` would start a server with the current
  # environment, which is not a readiness signal for that environment.)
  local port="${SCCACHE_SERVER_PORT:-4226}"
  [ -n "${SCCACHE_SERVER_UDS:-}" ] && return 1
  { exec 3<>"/dev/tcp/127.0.0.1/$port"; } 2>/dev/null || return 1
  exec 3>&-
  sccache --show-stats --stats-format=json 2>/dev/null | jq -r '.cache_location // empty'
}

sccache_backend_identity() {
  # Full backend identity of the configuration this tool would start a
  # server with: scheme, endpoint, bucket/root, region, and the tiered key
  # prefix. Public metadata only; recorded per server port so a later run
  # can tell whether the running server serves *this* backend.
  printf '%s\n' "$OBJ_SCHEME" "$OBJ_ENDPOINT" "$OBJ_ROOT" "$OBJ_REGION" "$SCC_PREFIX" | sha256sum | cut -d' ' -f1
}

sccache_state_file() {
  printf '%s/agentic-ci-cache-sccache-%s.id' "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}" "${SCCACHE_SERVER_PORT:-4226}"
}

sccache_run() {
  # The child's exit status is the exit status of this command: the build is
  # never swallowed. Cache preparation and backend failures degrade to an
  # uncached run and are reported on stderr (stdout belongs to the child).
  local probe want location
  [ "$#" -gt 0 ] || die "sccache run requires a command after --"
  REPORT_FD=2
  if ! sccache_prepare; then
    sccache_uncached
    exec "$@"
  fi
  if ! command -v sccache >/dev/null 2>&1; then
    report sccache-statistics sccache "$OBJ_LABEL" failed "sccache is not on PATH; running uncached" "$(sccache_identity_json)"
    sccache_uncached
    exec "$@"
  fi
  # A running server keeps the configuration it started with. Reuse it only
  # when it was started by this tool for exactly this backend identity and
  # still reports this tier's namespace (statistics then accumulate across
  # `run` invocations); otherwise replace it. An explicit start is
  # the readiness probe: sccache validates the backend before listening, so
  # an unreachable backend degrades to an uncached build here instead of
  # failing every compile through the wrapper.
  local identity state
  identity="$(sccache_backend_identity)"
  state="$(sccache_state_file)"
  want="$SCC_PREFIX"
  if location="$(sccache_server_location)" && [ -n "$location" ] && [[ "$location" == *"$want"* ]] \
    && [ -r "$state" ] && [ "$(cat -- "$state")" = "$identity" ]; then
    :
  else
    sccache --stop-server >/dev/null 2>&1 || true
    rm -f -- "$state"
    if ! probe="$(SCCACHE_STARTUP_TIMEOUT="${AGENTIC_SCCACHE_STARTUP_TIMEOUT:-20}" sccache --start-server 2>&1)"; then
      report sccache-statistics sccache "$OBJ_LABEL" failed "sccache server startup failed: $(grep -m1 -E 'error|failed' <<<"$probe" | tr -d '\r'); running uncached" "$(sccache_identity_json)"
      sccache_uncached
      exec "$@"
    fi
    printf '%s' "$identity" >"$state"
  fi
  # A server that dies mid-build must not fail the compile either.
  export SCCACHE_IGNORE_SERVER_IO_ERROR=1
  report sccache-statistics sccache "$OBJ_LABEL" ready "sccache server ready; running wrapped" "$(sccache_identity_json)"
  exec "$@"
}

sccache_stats() {
  local out
  sccache_prepare || return 0
  if ! command -v sccache >/dev/null 2>&1; then
    report sccache-statistics sccache "$OBJ_LABEL" failed "sccache is not on PATH"
    return 0
  fi
  if out="$(sccache --show-stats --stats-format=json 2>&1)" && jq -e . <<<"$out" >/dev/null 2>&1; then
    report sccache-statistics sccache "$OBJ_LABEL" reported "sccache statistics collected" "$(jq -c --argjson s "$out" '. + {statistics: $s}' <<<"$(sccache_identity_json)")"
  else
    report sccache-statistics sccache "$OBJ_LABEL" failed "sccache statistics unavailable: $(tail -n 1 <<<"$out" | tr -d '\r')" "$(sccache_identity_json)"
  fi
}

# --- uv -----------------------------------------------------------------------

UV_PLATFORM=""
UV_ABI=""
UV_GEN=""
UV_LOCK=""
UV_DETAIL=""
UV_DIR=""

uv_cache_dir() {
  local rel
  rel="$(pget "$1" .cacheDir)"
  if [ -n "${UV_CACHE_DIR:-}" ]; then
    UV_DIR="$UV_CACHE_DIR"
  else
    case "$rel" in
      /*) UV_DIR="$rel" ;;
      *) UV_DIR="$PWD/${rel:-.ci-cache/uv}" ;;
    esac
  fi
}

uv_identity() {
  local py lock
  if ! command -v uv >/dev/null 2>&1; then
    UV_DETAIL="uv is not on PATH"
    return 1
  fi
  UV_GEN="$(sanitize_segment "${AGENTIC_UV_CACHE_GENERATION:-$(uv --version 2>/dev/null | awk '{print $2}')}")"
  # Identity resolution must not populate the cache directory itself (uv
  # writes interpreter metadata on `python find`), so it runs against a
  # throwaway cache.
  local scratch
  scratch="$(mktemp -d)"
  py="$(UV_CACHE_DIR="$scratch" UV_PYTHON_DOWNLOADS=never uv python find 2>/dev/null)" \
    || py="$(UV_CACHE_DIR="$scratch" UV_PYTHON_DOWNLOADS=never UV_PYTHON_PREFERENCE=only-system uv python find 2>/dev/null)" \
    || py=""
  rm -rf -- "$scratch"
  # uv's managed-installation discovery needs a system ELF interpreter to
  # probe; where that is unavailable (hermetic sandboxes), fall back to the
  # interpreter uv itself would honour: UV_PYTHON, then python3 on PATH.
  if [ -z "$py" ] && [ -n "${UV_PYTHON:-}" ] && [ -x "${UV_PYTHON}" ]; then
    py="$UV_PYTHON"
  fi
  if [ -z "$py" ]; then
    py="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  fi
  if [ -z "$py" ]; then
    UV_DETAIL="no Python interpreter is available for the ABI identity (uv discovery, UV_PYTHON, and PATH all failed)"
    return 1
  fi
  if ! UV_ABI="$("$py" -c 'import sys, sysconfig; print(sysconfig.get_config_var("SOABI") or sys.implementation.cache_tag)' 2>/dev/null)" || [ -z "$UV_ABI" ]; then
    UV_DETAIL="Python ABI identity could not be resolved from $py"
    return 1
  fi
  UV_ABI="$(sanitize_segment "$UV_ABI")"
  lock="${AGENTIC_UV_LOCK_FILE:-uv.lock}"
  if [ ! -r "$lock" ]; then
    UV_DETAIL="lock input '$lock' is missing; the uv cache identity is incomplete"
    return 1
  fi
  UV_LOCK="$(sha256sum -- "$lock" | cut -d' ' -f1)"
  UV_PLATFORM="$(platform_id)"
  return 0
}

uv_key() {
  # uv_key PROFILE_JSON TIER
  local key_prefix
  key_prefix="$(pget "$1" .keyPrefix)"
  printf '%s/%s/%s/uv/%s/%s/%s/%s.tar.zst' "${key_prefix:-ci}" "$REPOSITORY" "$2" "$UV_PLATFORM" "$UV_ABI" "$UV_GEN" "$UV_LOCK"
}

uv_identity_json() {
  jq -nc --arg platform "$UV_PLATFORM" --arg abi "$UV_ABI" --arg gen "$UV_GEN" --arg lock "$UV_LOCK" --arg key "$1" --arg dir "$UV_DIR" \
    '{identity: {platform: $platform, python_abi: $abi, uv_cache_generation: $gen, lock_input: $lock, key: $key, cache_dir: $dir}}'
}

uv_env() {
  local profile
  REPORT_FD=2
  profile="$(profile_json python)"
  if [ -z "$profile" ]; then
    report uv-cache-summary uv-cache-environment none skipped "python profile is not part of the contract"
    return 0
  fi
  uv_cache_dir "$profile"
  printf 'UV_CACHE_DIR=%s\n' "$UV_DIR"
}

TMP_ARCHIVE=""
TMP_STAGING=""
cleanup_uv_tmp() {
  [ -n "$TMP_ARCHIVE" ] && rm -f -- "$TMP_ARCHIVE" "$TMP_ARCHIVE.err"
  [ -n "$TMP_STAGING" ] && rm -rf -- "$TMP_STAGING"
  return 0
}

uv_content_entries() {
  # Cache content other than uv's housekeeping (.lock, CACHEDIR.TAG,
  # .gitignore) and the interpreter metadata bucket.
  find "$1" -type f ! -name .lock ! -name CACHEDIR.TAG ! -name .gitignore ! -path "$1/interpreter-v*/*" -print -quit
}

path_stays_inside() {
  # path_stays_inside DIR TARGET -> 0 when DIR/TARGET (both relative to the
  # archive root) never rises above the root.
  local joined depth=0 seg
  case "$2" in /*) return 1 ;; esac
  joined="$1/$2"
  IFS=/ read -r -a _segs <<<"$joined"
  for seg in "${_segs[@]}"; do
    case "$seg" in
      "" | .) ;;
      ..)
        depth=$((depth - 1))
        [ "$depth" -lt 0 ] && return 1
        ;;
      *) depth=$((depth + 1)) ;;
    esac
  done
  return 0
}

UV_ARCHIVE_DETAIL=""
uv_archive_safe() {
  # uv_archive_safe ARCHIVE -> 0 when every member stays inside the cache
  # directory and the unpacked size is within the restore bound.
  local name listing total max
  max="${AGENTIC_UV_RESTORE_MAX_BYTES:-${AGENTIC_UV_PUBLISH_MAX_BYTES:-2147483648}}"
  if ! listing="$(tar --zstd -tvf "$1" 2>/dev/null)"; then
    UV_ARCHIVE_DETAIL="archive is not a readable zstd tarball"
    return 1
  fi
  while IFS= read -r name; do
    case "$name" in
      /* | ../* | */../* | */.. | ..)
        UV_ARCHIVE_DETAIL="archive member '$name' escapes the cache directory"
        return 1
        ;;
    esac
  done < <(tar --zstd -tf "$1")
  # Only regular files, directories, and relative links that stay inside.
  if grep -qE '^[bcps]' <<<"$listing"; then
    UV_ARCHIVE_DETAIL="archive contains a device, pipe, or socket member"
    return 1
  fi
  # Links are legitimate inside a uv cache (relative, often through `..`);
  # they must resolve inside the root once joined with the member's directory.
  local member target
  while IFS=$'\t' read -r member target; do
    if [ -z "$target" ] || ! path_stays_inside "$(dirname -- "$member")" "$target"; then
      UV_ARCHIVE_DETAIL="archive link '$member' -> '$target' escapes the cache directory"
      return 1
    fi
  done < <(grep -E '^[lh]' <<<"$listing" | awk '{
      n = index($0, " -> "); if (n == 0) n = index($0, " link to ");
      if (n == 0) { print "\t"; next }
      head = substr($0, 1, n - 1); sep = (index($0, " -> ") == n) ? 4 : 9;
      target = substr($0, n + sep);
      m = split(head, f, " "); member = f[6]; for (i = 7; i <= m; i++) member = member " " f[i];
      print member "\t" target
    }')
  total="$(awk '$1 ~ /^-/ {s += $3} END {print s + 0}' <<<"$listing")"
  if [ "$total" -gt "$max" ]; then
    UV_ARCHIVE_DETAIL="archive unpacks to $total bytes, above the restore bound of $max"
    return 1
  fi
  return 0
}

uv_restore() {
  local profile key tier status bytes
  profile="$(profile_json python)"
  if [ -z "$profile" ]; then
    report uv-cache-summary uv-cache-restore none skipped "python profile is not part of the contract"
    return 0
  fi
  object_backend "$profile"
  uv_cache_dir "$profile"
  if ! uv_identity; then
    report uv-cache-summary uv-cache-restore "$OBJ_LABEL" skipped "$UV_DETAIL"
    return 0
  fi
  key="$(uv_key "$profile" "$TRUST_TIER")"
  # Restore only ever populates an absent cache directory (or one holding
  # nothing but uv's own housekeeping): nothing outside it is touched and
  # no cache content is deleted.
  if [ -d "$UV_DIR" ] && [ -n "$(uv_content_entries "$UV_DIR")" ]; then
    report uv-cache-summary uv-cache-restore "$OBJ_LABEL" skipped "cache directory $UV_DIR is already populated; restore runs before the cache is used" "$(uv_identity_json "$key")"
    return 0
  fi
  local cred=0
  object_credentials_ready "$profile" || cred=$?
  case "$cred" in
    0) ;;
    1)
      report uv-cache-summary uv-cache-restore "$OBJ_LABEL" refused "$CRED_DETAIL" "$(uv_identity_json "$key")"
      return 0
      ;;
    *)
      report uv-cache-summary uv-cache-restore "$OBJ_LABEL" failed "$CRED_DETAIL" "$(uv_identity_json "$key")"
      return 0
      ;;
  esac
  scrub_tier_env

  # Exact identity only. A pull request may fall back to the protected
  # baseline with the same identity; protected never reads pull-request keys.
  local -a candidates=("$TRUST_TIER")
  [ "$TRUST_TIER" = pull-request ] && candidates+=(protected)
  trap cleanup_uv_tmp EXIT
  TMP_ARCHIVE="$(mktemp)"
  for tier in "${candidates[@]}"; do
    key="$(uv_key "$profile" "$tier")"
    obj_exists "$key" && status=0 || status=$?
    case "$status" in
      0)
        if ! obj_get "$key" "$TMP_ARCHIVE" 2>"$TMP_ARCHIVE.err"; then
          report uv-cache-summary uv-cache-restore "$OBJ_LABEL" failed "uv cache archive from the $tier namespace could not be fetched: $(tail -n 1 "$TMP_ARCHIVE.err" | tr -d '\r')" "$(uv_identity_json "$key")"
          return 0
        fi
        if ! uv_archive_safe "$TMP_ARCHIVE"; then
          report uv-cache-summary uv-cache-restore "$OBJ_LABEL" failed "uv cache archive from the $tier namespace rejected: $UV_ARCHIVE_DETAIL" "$(uv_identity_json "$key")"
          return 0
        fi
        mkdir -p -- "$(dirname -- "$UV_DIR")"
        TMP_STAGING="$(mktemp -d "$(dirname -- "$UV_DIR")/.uv-restore.XXXXXX")"
        if ! tar --zstd -xf "$TMP_ARCHIVE" -C "$TMP_STAGING" --no-same-owner; then
          report uv-cache-summary uv-cache-restore "$OBJ_LABEL" failed "uv cache archive from the $tier namespace could not be unpacked; cache directory left untouched" "$(uv_identity_json "$key")"
          return 0
        fi
        # Only uv housekeeping can be present here (checked above).
        [ -d "$UV_DIR" ] && rm -rf -- "$UV_DIR"
        if ! mv -- "$TMP_STAGING" "$UV_DIR"; then
          report uv-cache-summary uv-cache-restore "$OBJ_LABEL" failed "restored cache could not be moved into $UV_DIR" "$(uv_identity_json "$key")"
          return 0
        fi
        TMP_STAGING=""
        bytes="$(stat -c %s "$TMP_ARCHIVE" 2>/dev/null || stat -f %z "$TMP_ARCHIVE")"
        report uv-cache-summary uv-cache-restore "$OBJ_LABEL" restored "exact-identity uv cache restored from the $tier namespace" "$(jq -c --arg t "$tier" --argjson b "$bytes" '. + {source_tier: $t, bytes: $b}' <<<"$(uv_identity_json "$key")")"
        return 0
        ;;
      1) ;;
      *)
        report uv-cache-summary uv-cache-restore "$OBJ_LABEL" failed "object backend error while probing the $tier namespace: $OBJ_ERROR" "$(uv_identity_json "$key")"
        return 0
        ;;
    esac
  done
  report uv-cache-summary uv-cache-restore "$OBJ_LABEL" miss "no exact-identity uv cache entry exists for this tier (or the protected baseline for pull requests)" "$(uv_identity_json "$(uv_key "$profile" "$TRUST_TIER")")"
}

uv_publish() {
  local profile key bytes max status
  profile="$(profile_json python)"
  if [ -z "$profile" ]; then
    report publication-result uv-cache-publication none skipped "python profile is not part of the contract"
    return 0
  fi
  object_backend "$profile"
  uv_cache_dir "$profile"
  if ! uv_identity; then
    report publication-result uv-cache-publication "$OBJ_LABEL" skipped "$UV_DETAIL"
    return 0
  fi
  key="$(uv_key "$profile" "$TRUST_TIER")"
  if [ ! -d "$UV_DIR" ]; then
    report publication-result uv-cache-publication "$OBJ_LABEL" skipped-empty "uv cache directory $UV_DIR does not exist" "$(uv_identity_json "$key")"
    return 0
  fi
  if ! UV_CACHE_DIR="$UV_DIR" uv cache prune --ci >&2; then
    report publication-result uv-cache-publication "$OBJ_LABEL" failed "uv cache prune --ci failed; nothing was published" "$(uv_identity_json "$key")"
    return 0
  fi
  # uv's housekeeping files and the interpreter metadata bucket are not
  # worth a publication on their own.
  if [ -z "$(uv_content_entries "$UV_DIR")" ]; then
    report publication-result uv-cache-publication "$OBJ_LABEL" skipped-empty "uv cache holds no publishable entries after pruning" "$(uv_identity_json "$key")"
    return 0
  fi
  bytes="$(du -sk -- "$UV_DIR" | cut -f1)"
  bytes="$((bytes * 1024))"
  max="${AGENTIC_UV_PUBLISH_MAX_BYTES:-2147483648}"
  if [ "$bytes" -gt "$max" ]; then
    report publication-result uv-cache-publication "$OBJ_LABEL" skipped-bound "pruned uv cache ($bytes bytes) exceeds the publication bound of $max bytes" "$(jq -c --argjson b "$bytes" --argjson m "$max" '. + {bytes: $b, bound: $m}' <<<"$(uv_identity_json "$key")")"
    return 0
  fi
  local cred=0
  object_credentials_ready "$profile" || cred=$?
  case "$cred" in
    0) ;;
    1)
      report publication-result uv-cache-publication "$OBJ_LABEL" refused "$CRED_DETAIL" "$(uv_identity_json "$key")"
      return 0
      ;;
    *)
      report publication-result uv-cache-publication "$OBJ_LABEL" failed "$CRED_DETAIL" "$(uv_identity_json "$key")"
      return 0
      ;;
  esac
  scrub_tier_env

  obj_exists "$key" && status=0 || status=$?
  case "$status" in
    0)
      report publication-result uv-cache-publication "$OBJ_LABEL" skipped-exists "an entry with this exact identity is already published; keys are immutable" "$(uv_identity_json "$key")"
      return 0
      ;;
    1) ;;
    *)
      report publication-result uv-cache-publication "$OBJ_LABEL" failed "object backend error while probing the $TRUST_TIER namespace: $OBJ_ERROR" "$(uv_identity_json "$key")"
      return 0
      ;;
  esac

  trap cleanup_uv_tmp EXIT
  TMP_ARCHIVE="$(mktemp)"
  if ! tar --zstd -cf "$TMP_ARCHIVE" -C "$UV_DIR" --exclude=./.lock .; then
    report publication-result uv-cache-publication "$OBJ_LABEL" failed "uv cache archive could not be created" "$(uv_identity_json "$key")"
    return 0
  fi
  if obj_put "$TMP_ARCHIVE" "$key" 2>"$TMP_ARCHIVE.err"; then
    report publication-result uv-cache-publication "$OBJ_LABEL" published "pruned uv cache published under the $TRUST_TIER namespace" "$(jq -c --argjson b "$(stat -c %s "$TMP_ARCHIVE" 2>/dev/null || stat -f %z "$TMP_ARCHIVE")" '. + {bytes: $b}' <<<"$(uv_identity_json "$key")")"
  else
    report publication-result uv-cache-publication "$OBJ_LABEL" failed "uv cache upload failed: $(tail -n 1 "$TMP_ARCHIVE.err" | tr -d '\r'); build result remains authoritative" "$(uv_identity_json "$key")"
  fi
}

# --- identity -----------------------------------------------------------------

identity() {
  local nix_p rust_p python_p sc uv
  nix_p="$(profile_json nix)"
  rust_p="$(profile_json rust)"
  python_p="$(profile_json python)"
  sc='null'
  uv='null'
  if [ -n "$rust_p" ]; then
    if sccache_identity "$rust_p"; then
      sc="$(sccache_identity_json | jq -c .identity)"
    else
      sc="$(jq -nc --arg d "$SCC_DETAIL" '{error: $d}')"
    fi
  fi
  if [ -n "$python_p" ]; then
    uv_cache_dir "$python_p"
    if uv_identity; then
      uv="$(uv_identity_json "$(uv_key "$python_p" "$TRUST_TIER")" | jq -c .identity)"
    else
      uv="$(jq -nc --arg d "$UV_DETAIL" '{error: $d}')"
    fi
  fi
  jq -nc \
    --arg repository "$REPOSITORY" \
    --arg trust_tier "$TRUST_TIER" \
    --arg platform "$(platform_id)" \
    --argjson nix "$([ -n "$nix_p" ] && jq -c '{readEndpoints, keyInputs}' <<<"$nix_p" || echo null)" \
    --argjson sccache "$sc" \
    --argjson uv "$uv" \
    '{repository: $repository, trust_tier: $trust_tier, platform: $platform, nix: $nix, sccache: $sccache, uv: $uv}'
}

# --- main ---------------------------------------------------------------------

main() {
  [ "$#" -ge 1 ] || usage
  local group="$1"
  shift
  load_contract
  resolve_repository
  resolve_trust_tier
  case "$group" in
    identity) identity ;;
    nix)
      case "${1:-}" in
        config) nix_config ;;
        publish)
          shift
          nix_publish "$@"
          ;;
        *) usage ;;
      esac
      ;;
    sccache)
      case "${1:-}" in
        env) sccache_env ;;
        run)
          shift
          [ "${1:-}" = "--" ] && shift
          sccache_run "$@"
          ;;
        stats) sccache_stats ;;
        *) usage ;;
      esac
      ;;
    uv)
      case "${1:-}" in
        env) uv_env ;;
        restore) uv_restore ;;
        publish) uv_publish ;;
        *) usage ;;
      esac
      ;;
    *) usage ;;
  esac
}

main "$@"
