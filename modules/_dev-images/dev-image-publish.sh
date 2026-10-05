# dev-image-publish: publish one image package as a digest-pinned multi-arch
# OCI index (Workbench dev images). Packaged by builder.nix.
pkg=${1:?usage: dev-image-publish <package> (for example bph-dev-base)}
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "dev-image-publish: working tree is dirty; commit first so the tag names a real revision" >&2
  exit 1
fi
rev=$(git rev-parse --short=12 HEAD)
# Evaluate the committed revision, never the live working tree.
flake="git+file://$(git rev-parse --show-toplevel)?rev=$(git rev-parse HEAD)&submodules=1"
repo=$(nix eval --raw "$flake#packages.aarch64-linux.$pkg.imageName")
tag="multiarch-$rev"

if [ -z "${DOCKER_CONFIG:-}" ] && [ -f "$HOME/.config/containers/auth.json" ]; then
  DOCKER_CONFIG=$(mktemp -d)
  trap 'rm -rf "$DOCKER_CONFIG"' EXIT
  ln -s "$HOME/.config/containers/auth.json" "$DOCKER_CONFIG/config.json"
  export DOCKER_CONFIG
fi

if existing=$(crane digest "$repo:$tag" 2>/dev/null); then
  echo "$repo:$tag already published: $existing (tags are never moved)" >&2
  echo "$repo@$existing"
  exit 0
fi

manifests=()
for pair in aarch64-linux:arm64 x86_64-linux:amd64; do
  sys=${pair%%:*} arch=${pair##*:}
  image=$(nix build --no-link --print-out-paths "$flake#packages.$sys.$pkg")
  skopeo --insecure-policy copy --format oci "nix:$image" "docker://$repo:$rev-$arch" >&2
  digest=$(crane digest "$repo:$rev-$arch")
  echo "$arch: $repo@$digest" >&2
  manifests+=(-m "$repo@$digest")
done
crane index append "${manifests[@]}" -t "$repo:$tag" >&2
echo "$repo@$(crane digest "$repo:$tag")"
