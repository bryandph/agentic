# Core org-neutral knowledge fragments (task 3.5). Subject cards every
# environment shares; env layers and repos add their own into the same
# `agentic.knowledge` attrset. Each card stays within the size bound
# and points at deeper sources visible to every consumer of core
# (upstream docs, or `mem:knowledge/*` memories core itself ships via
# the memory plane).
{
  agentic.knowledge = {
    nix-dendritic = {
      file = ../../fragments/nix-dendritic.md;
      title = "Nix: dendritic flake-parts pattern";
    };
    rust-patterns = {
      file = ../../fragments/rust-patterns.md;
      title = "Rust projects";
    };
    python-uv = {
      file = ../../fragments/python-uv.md;
      title = "Python projects (uv-first)";
    };
    kubernetes = {
      file = ../../fragments/kubernetes.md;
      title = "Kubernetes (GitOps)";
    };
    networking = {
      file = ../../fragments/networking.md;
      title = "Networking as declared topology";
    };
    pki = {
      file = ../../fragments/pki.md;
      title = "Private PKI";
    };
    sops-vault = {
      file = ../../fragments/sops-vault.md;
      title = "Secrets handling";
    };
    serena-usage = {
      file = ../../fragments/serena-usage.md;
      title = "Serena memory discipline";
    };
  };
}
