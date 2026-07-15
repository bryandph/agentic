Two secret planes, one rule: **values never enter an agent's context,
rendered artifacts, or the nix store.**

- *At-rest host secrets*: SOPS-encrypted files (age recipients per
  host, operator key as anchor); the encryption ruleset (.sops.yaml)
  is generated from the fleet contract, never hand-edited. Never read,
  diff, or decode SOPS files — verify by existence, size (`wc -c`), or
  hash, and tell the operator immediately if a raw value ever surfaces.
- *Runtime credentials*: sourced by a CLI (vault/OpenBao-compatible kv
  or the environment's declared backend) at process start — wrapped
  binaries for stdio processes, `''${VAR}` client-side expansion +
  bootstrap export for HTTP configs. Reads and writes to the secret
  store are fine; SURFACING the bytes is not.
- Safe diagnostics: `wc -c`, `sha256sum`, `jq 'keys'`, `ls -la` —
  anything that proves presence/identity without emitting value bytes.
  A secret an agent has seen is compromised: rotate it.

Deeper sources: https://github.com/Mic92/sops-nix,
https://openbao.org/docs/.
