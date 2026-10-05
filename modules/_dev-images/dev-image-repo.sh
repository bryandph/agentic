# dev-image-repo: build (and publish) a repository's warm environment image
# (OpenSpec distributable-dev-environments, D9). Packaged by dev-images.nix.
# Run from the repository's checkout (devenv's flake integration reads PWD):
#
#   dev-image-repo [--shell default] [--repository <registry/path>]
#                  [--branch-tag main] [--builder <flakeref>]
#                  [--systems "aarch64-linux x86_64-linux"] [--no-publish]
#                  [--build <system> | --join] [--authfile <path>]
#
# Default: build every system, then join. CI splits it per lane: `--build
# <system>` on each architecture's lane, then `--join` (index + branch tag).
# --systems always names every system of the identity.
#
# Identity: per architecture env-<id>-<arch>, where <id> hashes that system's
# devShell inputDerivation drv path; the index env-<id> hashes the per-arch
# manifest digests. A published identity is not rebuilt; the branch tag is
# (re)pointed at it. env-* tags never move.

shell=default repository="" branch=main builder=${DEV_IMAGE_BUILDER:-} publish=true
mode="all" only="" authfile=""
systems="aarch64-linux x86_64-linux"
while [ $# -gt 0 ]; do
  case "$1" in
    --shell) shell=$2; shift 2 ;;
    --repository) repository=$2; shift 2 ;;
    --branch-tag) branch=$2; shift 2 ;;
    --builder) builder=$2; shift 2 ;;
    --systems) systems=$2; shift 2 ;;
    --no-publish) publish=false; shift ;;
    --build) mode="build" only=$2; shift 2 ;;
    --join) mode="join"; shift ;;
    --authfile) authfile=$2; shift 2 ;;
    -h | --help)
      echo "usage: dev-image-repo [--shell S] [--repository R] [--branch-tag B] [--builder F] [--systems \"...\"] [--no-publish]"
      exit 0
      ;;
    *) echo "dev-image-repo: unknown argument: $1" >&2; exit 2 ;;
  esac
done

top=$(git rev-parse --show-toplevel)
cd "$top"
name=$(basename "$(git remote get-url origin)" .git)
if [ -z "$repository" ]; then
  if [ -z "${DEV_IMAGE_REGISTRY:-}" ]; then
    echo "dev-image-repo: pass --repository <registry/path> or set DEV_IMAGE_REGISTRY (images go to \$DEV_IMAGE_REGISTRY/<repo>-dev)" >&2
    exit 2
  fi
  repository="$DEV_IMAGE_REGISTRY/$name-dev"
fi
# The builder flake provides legacyPackages.<system>.devImages.mkWarm and
# .base. By default the checkout itself (a repository that instantiates the
# images); others pass --builder. The working tree, not ?rev=: with a pinned
# rev Nix re-fetches submodules from the committed .gitmodules URLs, which CI
# rewrites only in the working tree; unpinned, it uses the checkout.
builder=${builder:-git+file://$top?submodules=1}
export NIX_CONFIG="extra-experimental-features = pipe-operators
accept-flake-config = true"

# 1. Identity. Each system's env-<id>-<arch> comes from that system's own
# devShell build-environment derivation: evaluating another system's shell
# can need import-from-derivation builds for that platform (nixspace's
# devenv-nixpkgs-patched), which a single-architecture CI lane cannot run.
# Every per-arch manifest is also tagged sha-<commit>-<arch>; the index
# identity hashes the per-arch manifest digests, which the reproducible
# images fix for a given environment.
rev=$(git rev-parse --short=12 HEAD)
# The id covers the environment, the image it is layered on (tools, policy,
# base digest) and the builder recipe (warm-only logic such as the
# environment-bound policy): any of them changing must publish a new image.
envId() {
  { nix eval --impure --raw ".#devShells.$1.$shell.inputDerivation.drvPath"
    echo
    nix eval --impure --raw "$builder#legacyPackages.$1.devImages.base.drvPath"
    echo
    nix eval --impure --raw "$builder#legacyPackages.$1.devImages.recipe" 2>/dev/null || true
  } | sha256sum | cut -c1-16
}
echo "dev-image-repo: $repository (shell $shell, commit $rev)" >&2

authfile=${authfile:-${REGISTRY_AUTH_FILE:-$HOME/.config/containers/auth.json}}
if [ -f "$authfile" ]; then
  export REGISTRY_AUTH_FILE=$authfile
  if [ -z "${DOCKER_CONFIG:-}" ]; then
    DOCKER_CONFIG=$(mktemp -d)
    trap 'rm -rf "$DOCKER_CONFIG"' EXIT
    ln -s "$(realpath "$authfile")" "$DOCKER_CONFIG/config.json"
    export DOCKER_CONFIG
  fi
fi
archOf() {
  case "${1%%-*}" in aarch64) echo arm64 ;; x86_64) echo amd64 ;; *) echo "${1%%-*}" ;; esac
}

join() {
  manifests=() digests=()
  for sys in $systems; do
    d=$(crane digest "$repository:sha-$rev-$(archOf "$sys")")
    manifests+=(-m "$repository@$d")
    digests+=("$d")
  done
  tag="env-$(printf '%s\n' "${digests[@]}" | sort | sha256sum | cut -c1-16)"
  if ! crane digest "$repository:$tag" >/dev/null 2>&1; then
    crane index append "${manifests[@]}" -t "$repository:$tag" >&2
  else
    echo "dev-image-repo: $tag already published" >&2
  fi
  crane tag "$repository:$tag" "$branch" >&2
  echo "$repository:$tag -> $branch" >&2
  echo "$repository@$(crane digest "$repository:$tag")"
}
if [ "$mode" = join ]; then
  join
  exit 0
fi

for sys in $systems; do
  if [ "$mode" = build ] && [ "$sys" != "$only" ]; then continue; fi
  arch=$(archOf "$sys")
  tag="env-$(envId "$sys")"
  if $publish && crane digest "$repository:$tag-$arch" >/dev/null 2>&1; then
    echo "dev-image-repo: $tag-$arch already published; tagging sha-$rev-$arch" >&2
    crane tag "$repository:$tag-$arch" "sha-$rev-$arch" >&2
    continue
  fi

  # 2. Realise the build environment (what nix-direnv/devenv would pin).
  env=$(nix build --impure --no-link --print-out-paths ".#devShells.$sys.$shell.inputDerivation")
  # The flake's own inputs: evaluation needs their sources (nixpkgs, ...),
  # which the build environment's closure does not contain. Only `.inputs`:
  # the flake's own source is the checkout (and may carry secrets/).
  mapfile -t inputs < <(nix flake archive --json | jq -r '.inputs | .. | .path? // empty')
  warm=("$env" "${inputs[@]}")

  # 3. No secrets (spec: Warm images carry no secrets). Content-based: the
  # closure legitimately holds `*-secrets` runner scripts that resolve
  # credentials from OpenBao at runtime, so store-path names prove nothing.
  # Refuse SOPS-encrypted values (every SOPS format wraps them as
  # ENC[AES256_GCM,...]) and age secret keys or armored age files. PEM
  # headers are not checked: upstream parsers, docs and test fixtures in a
  # typical closure carry them by design (110 hits in nixspace's, none ours).
  # Scan what could hold our secrets: the build environment and the private
  # inputs (path, git, the forge). Public inputs (github, gitlab, sourcehut,
  # tarball) are pinned by narHash to public content and carry upstream test
  # fixtures by design (sops-nix's encrypted test-assets, for one).
  mapfile -t public < <(nix flake metadata --json | jq -r '[.locks.nodes[] | .locked? // empty
    | select(.type == "github" or .type == "gitlab" or .type == "sourcehut" or .type == "tarball")
    | .narHash] | unique[]')
  scan=("$env")
  for input in "${inputs[@]}"; do
    nar=$(nix path-info --json "$input" | jq -r '(.[]? // .[keys[0]]) | .narHash')
    if ! printf '%s\n' "${public[@]}" | grep -qxF "$nar"; then scan+=("$input"); fi
  done
  echo "$sys: scanning the environment and $((${#scan[@]} - 1)) private inputs" >&2
  closure=$(nix-store -qR "${scan[@]}")
  # Captured rather than piped through head: under pipefail an early-closed
  # pipe would report "no match" for a closure that has one.
  hits=$(xargs grep -rIl -e 'ENC\[AES256_GCM,' -e 'AGE-SECRET-KEY-1' \
    -e 'BEGIN AGE ENCRYPTED FILE' <<< "$closure" || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed -n '1,10p' >&2
    echo "dev-image-repo: secret material in the $sys closure; refusing" >&2
    exit 1
  fi

  # 4. The image: dev-nix layers plus the environment, one database.
  image=$(nix build --impure --no-link --print-out-paths --expr "
    (builtins.getFlake \"$builder\").legacyPackages.$sys.devImages.mkWarm {
      name = \"$repository\";
      tag = \"$tag-$arch\";
      warmPaths = map builtins.storePath (builtins.fromJSON ''$(printf '%s\n' "${warm[@]}" | jq -R . | jq -sc .)'');
    }")
  echo "$sys: environment $env, image $image" >&2
  if $publish; then
    skopeo --insecure-policy copy --format oci "nix:$image" "docker://$repository:$tag-$arch" >&2
    crane tag "$repository:$tag-$arch" "sha-$rev-$arch" >&2
  fi
done

if $publish && [ "$mode" = all ]; then
  join
fi
