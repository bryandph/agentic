# dev-verify: run a repository's declared steps and record structured evidence
# (OpenSpec distributable-dev-environments, D7). Packaged by dev-images.nix.
#
#   dev-verify --repo <https-url|bundle-path> [--ref <ref>] [--dir <path>]
#              [--step <name>=<command>]... [--keep-going]
#
# Steps come from --step flags, else from the checkout's .dev-verify.json:
#   {"steps": [{"name": "test", "run": "uv run pytest"}]}
# Evidence lands in $DEV_VERIFY_EVIDENCE_DIR (default /sandbox/.evidence)/<run-id>/:
#   evidence.json, logs/<n>-<name>.log
# Result: pass (exit 0), fail (a step failed, exit 1), or error (clone,
# checkout, step source or a missing tool, exit 2). Nothing is ever pushed.

repo="" ref="" dir="" keep_going=false
steps=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo=$2; shift 2 ;;
    --ref) ref=$2; shift 2 ;;
    --dir) dir=$2; shift 2 ;;
    --step) steps+=("$2"); shift 2 ;;
    --keep-going) keep_going=true; shift ;;
    -h | --help)
      echo "usage: dev-verify --repo <url|bundle> [--ref <ref>] [--dir <path>] [--step <name>=<cmd>]... [--keep-going]"
      exit 0
      ;;
    *) echo "dev-verify: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$repo" ] || { echo "dev-verify: --repo is required" >&2; exit 2; }

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
evidence="${DEV_VERIFY_EVIDENCE_DIR:-/sandbox/.evidence}/$run_id"
mkdir -p "$evidence/logs"
dir=${dir:-/sandbox/$(basename "${repo%.git}" .bundle)}

records=$(mktemp)
echo '[]' > "$records"
result=pass commit="" error=""

record() { # name cmd exit duration log status
  jq --arg name "$1" --arg cmd "$2" --argjson exit "$3" --argjson dur "$4" \
    --arg log "$5" --arg status "$6" \
    '. + [{name: $name, cmd: $cmd, exitCode: $exit, durationS: $dur, log: $log, status: $status}]' \
    "$records" > "$records.new" && mv "$records.new" "$records"
}

finish() {
  jq -n --arg repo "$repo" --arg ref "$ref" --arg commit "$commit" \
    --arg image "${DEV_IMAGE_DIGEST:-unknown}" --arg platform "$(uname -m)" \
    --arg result "$result" --arg error "$error" --arg runId "$run_id" \
    --slurpfile steps "$records" \
    '{runId: $runId, repo: $repo, ref: $ref, commit: $commit, image: $image,
      platform: $platform, result: $result, steps: $steps[0]}
     + (if $error == "" then {} else {error: $error} end)' > "$evidence/evidence.json"
  rm -f "$records"
  echo "dev-verify: $result — $evidence/evidence.json" >&2
  case "$result" in pass) exit 0 ;; fail) exit 1 ;; *) exit 2 ;; esac
}

infra_error() { result=error error=$1; finish; }

# Source: clone (read-only credentials only, never pushed back) or bundle.
if [ ! -d "$dir/.git" ]; then
  git clone --quiet "$repo" "$dir" > "$evidence/logs/0-clone.log" 2>&1 ||
    infra_error "clone failed (see logs/0-clone.log)"
fi
cd "$dir" || infra_error "checkout directory missing: $dir"
if [ -n "$ref" ]; then
  { git fetch --quiet origin "$ref" 2>/dev/null || true; git checkout --quiet --detach "$ref" ||
    git checkout --quiet --detach FETCH_HEAD; } >> "$evidence/logs/0-clone.log" 2>&1 ||
    infra_error "checkout of $ref failed (see logs/0-clone.log)"
fi
commit=$(git rev-parse HEAD)

# Submodules: Nix evaluates a clean checkout as git+file?rev=…&submodules=1
# and re-fetches each submodule from its .gitmodules URL, which a worker
# cannot (and must not need to) reach. Point those URLs, in scp form and
# Nix's normalised ssh:// form, at the module repositories already in the
# checkout. Sandbox-local git config; nothing is fetched from the forge.
if [ -f .gitmodules ]; then
  while read -r key url; do
    name=${key#submodule.}
    name=${name%.url}
    path=$(git config -f .gitmodules --get "submodule.$name.path" || true)
    gitdir=$(git -C "$path" rev-parse --absolute-git-dir 2>/dev/null || true)
    [ -n "$gitdir" ] || continue
    git config --global --add "url.file://$gitdir.insteadOf" "$url"
    case "$url" in
      *@*:*) host=${url%%:*} repo=${url#*:}
        git config --global --add "url.file://$gitdir.insteadOf" "ssh://$host/$repo" ;;
    esac
  done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.url$')
fi

if [ ${#steps[@]} -eq 0 ]; then
  [ -f .dev-verify.json ] || infra_error "no --step given and no .dev-verify.json in $dir"
  mapfile -t steps < <(jq -r '.steps[] | "\(.name)=\(.run)"' .dev-verify.json) ||
    infra_error "unreadable .dev-verify.json"
fi

n=0
for step in "${steps[@]}"; do
  n=$((n + 1))
  name=${step%%=*} cmd=${step#*=}
  log="logs/$n-$name.log"
  if [ "$result" != pass ] && ! $keep_going; then
    record "$name" "$cmd" null 0 "" skipped
    continue
  fi
  start=$(date +%s)
  code=0
  bash -c "$cmd" > "$evidence/$log" 2>&1 || code=$?
  dur=$(($(date +%s) - start))
  if [ $code -eq 0 ]; then
    record "$name" "$cmd" 0 "$dur" "$log" passed
  elif [ $code -eq 126 ] || [ $code -eq 127 ]; then
    # Command not found or not executable: the environment, not the code.
    record "$name" "$cmd" "$code" "$dur" "$log" error
    result=error error="step $name: missing or non-executable tool (exit $code)"
  else
    record "$name" "$cmd" "$code" "$dur" "$log" failed
    if [ "$result" = pass ]; then result=fail; fi
  fi
done
finish
