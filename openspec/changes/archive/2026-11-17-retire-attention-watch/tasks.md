## 1. Retire the implementation

- [x] 1.1 Remove the watcher module/directory and package-list entries.
- [x] 1.2 Remove recovery broker samples, watcher reads and their flags; retain connector-snapshot classification and all fencing.
- [x] 1.3 Delete queue-sample/watcher fixtures and documentation, retaining other recovery cases.

## 2. Verify and archive

- [x] 2.1 Run `nix fmt --accept-flake-config` and the treefmt check.
- [x] 2.2 Run `nix build .#checks.aarch64-darwin.worker-recover` and `nix flake check --accept-flake-config` locally, without `--all-systems`.
- [x] 2.3 Inspect hook configuration and audit remaining retirement references. No pre-commit hooks configured in agentic; the coordinator confirmed formatter and flake checks are the applicable gates.
- [x] 2.4 Validate this change with OpenSpec and archive it, updating the durable spec.
- [x] 2.5 Prepare commits and verification evidence for coordinator review; do not merge or push.
