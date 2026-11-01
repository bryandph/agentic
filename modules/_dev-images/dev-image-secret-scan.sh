# Print paths containing SOPS-encrypted values, age secret keys or armored
# age files. Arguments are file/directory roots (normally Nix store paths).
# Like the warm-image gate, report hits on stdout, not via the exit status.
# Split patterns so neither this source nor its built script is a hit.
grep -rIl -e 'ENC\[''AES256_GCM,' -e 'AGE-SECRET-KEY''-1' \
  -e 'BEGIN AGE'' ENCRYPTED FILE' -- "$@" || true
