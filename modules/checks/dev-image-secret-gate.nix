{inputs, ...}: {
  perSystem = {
    pkgs,
    self',
    ...
  }: {
    checks.dev-image-secret-gate =
      pkgs.runCommand "dev-image-secret-gate" {
        nativeBuildInputs = [self'.packages.dev-image-secret-scan];
      } ''
        assert_clean() {
          hits=$(dev-image-secret-scan "$2")
          if [ -n "$hits" ]; then
            printf '%s: unexpected hits:\n%s\n' "$1" "$hits" >&2
            exit 1
          fi
          echo "$1: 0 hits" >> "$out"
        }
        assert_hit() {
          hits=$(dev-image-secret-scan "$2")
          if [ "$hits" != "$2" ]; then
            printf '%s: expected path %s, got %s\n' "$1" "$2" "$hits" >&2
            exit 1
          fi
          echo "$1: 1 hit, exact path reported" >> "$out"
        }

        assert_clean scanner-script ${self'.packages.dev-image-secret-scan}/bin/dev-image-secret-scan
        assert_clean repo-script ${self'.packages.dev-image-repo}/bin/dev-image-repo
        # The entire flake source, as present in a consumer's private inputs.
        assert_clean agentic-source ${inputs.self}

        mkdir fixtures
        printf '%s\n' "AGE-SECRET-KEY"'-1FAKE' > fixtures/age-key
        printf '%s\n' "-----BEGIN AGE"' ENCRYPTED FILE-----' > fixtures/age-armor
        printf '%s\n' "ENC["'AES256_GCM,data:fake,iv:fake,tag:fake,type:str]' > fixtures/sops
        assert_hit age-key "$PWD/fixtures/age-key"
        assert_hit age-armor "$PWD/fixtures/age-armor"
        assert_hit sops "$PWD/fixtures/sops"
        # In particular, the envelope's bracket must be literal, not a class.
        printf '%s\n' 'AGE-SECRET-KEY-' 'BEGIN AGE ENCRYPTED FIL' \
          "ENC["'AES256_GCM' 'ENCAES256_GCM,data:fake]' > fixtures/near-misses
        assert_clean near-misses "$PWD/fixtures/near-misses"

        hits=$(dev-image-secret-scan "$PWD/fixtures")
        test "$(printf '%s\n' "$hits" | wc -l)" -eq 3
        for path in age-key age-armor sops; do
          case "$hits" in *"$PWD/fixtures/$path"*) ;; *) exit 1 ;; esac
        done
        echo "recursive fixtures: 3 hits, all positive paths reported" >> "$out"
      '';
  };
}
