Rust projects here use **devenv** for the shell and keep packaging in
the repo's own flake wiring.

- Toolchain via `languages.rust` in devenv (channel + components:
  rustc, cargo, clippy, rustfmt, rust-analyzer) — never ad-hoc rustup.
- Pre-commit hooks: `clippy` and `rustfmt` are non-negotiable; fix the
  finding, never bypass the hook.
- Packaging (when the repo builds artifacts) composes `rust-overlay`
  and/or `crane` in the repo's own modules — the shell profile never
  owns the build.
- Prefer `cargo build`/`cargo test`/`cargo clippy` inside the dev
  shell; the shell pins openssl/pkg-config so native deps resolve.
- Embedded targets (cargo + probe-rs / flash tooling) keep their
  upstream workflow untouched — the agentic shell only adds workflow
  tooling, never wraps the build.

Deeper sources: https://devenv.sh/languages/ (rust),
https://github.com/oxalica/rust-overlay, https://github.com/ipetkov/crane.
