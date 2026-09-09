# CI cache contract shared by environment layers and consuming repos.
#
# Core defines the typed interface, the trust invariants, and the consumer-
# side client that implements them (`agentic-ci-cache`, built by
# _ci-cache-tool.nix from _ci-cache/agentic-ci-cache.sh). An environment
# layer supplies endpoints and runtime secret variable names; a repository
# requests the ecosystems it uses and remains responsible for its pipeline.
# Missing profiles are intentionally ignored so the same repo evaluates as an
# org-neutral consumer when no environment layer is imported.
#
# Credential convention (enforced by the client): every secret is read only
# from a trust-tier-prefixed variable, CI_CACHE_PROTECTED_<NAME>[_FILE] or
# CI_CACHE_PULL_REQUEST_<NAME>[_FILE]; a workflow mounts only its own tier.
{
  lib,
  config,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.agentic.ciCache;
  tool = import ./_ci-cache-tool.nix {inherit lib;};

  credentialEnvPrefixes = {
    protected = "CI_CACHE_PROTECTED_";
    pull-request = "CI_CACHE_PULL_REQUEST_";
  };

  profileCommon = {
    runtimeSecretEnv = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Base names of the runtime-provided secrets the cache client resolves
        through the trust-tier-prefixed variables (CI_CACHE_PROTECTED_<NAME>
        or CI_CACHE_PULL_REQUEST_<NAME>, each also accepting a _FILE variant).
        Values never enter the contract.
      '';
    };

    observability = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Structured cache results the consuming workflow must report.";
    };
  };

  nixProfileType = types.submodule {
    options =
      profileCommon
      // {
        readEndpoints = mkOption {
          type = types.listOf types.str;
          description = "Signed Nix substituters in preference order.";
        };

        protectedWriteEndpoint = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Authoritative closure-publication endpoint available only to protected workflows.";
        };

        pullRequestWriteEndpoint = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Untrusted quarantine endpoint for pull-request closures; it is never a protected substituter.";
        };

        trustedPublicKeys = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Public signing keys used to verify substituted Nix paths.";
        };

        keyInputs = mkOption {
          type = types.listOf types.str;
          default = [
            "repository"
            "architecture"
            "lock-input"
            "trust-tier"
          ];
          readOnly = true;
          description = "Inputs that select the Nix publication namespace; store paths retain their native content identity.";
        };

        publicationMode = mkOption {
          type = types.enum ["completed-closures"];
          default = "completed-closures";
          readOnly = true;
          description = "Bounded publication mode; cache-status walks are deliberately not part of the contract.";
        };
      };

    config = {
      observability = [
        "substitution-summary"
        "publication-result"
      ];
      # Protected endpoints over HTTP(S) authenticate with NIX_CACHE_TOKEN (or
      # a ready NIX_NETRC_FILE); s3:// endpoints use the AWS pair.
      runtimeSecretEnv = lib.mkDefault [
        "NIX_CACHE_TOKEN"
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
      ];
    };
  };

  rustProfileType = types.submodule {
    options =
      profileCommon
      // {
        endpoint = mkOption {
          type = types.str;
          description = "S3-compatible endpoint used by sccache.";
        };

        bucket = mkOption {
          type = types.str;
          description = "Object bucket used by sccache.";
        };

        region = mkOption {
          type = types.str;
          description = "S3 region identifier passed to sccache.";
        };

        keyPrefix = mkOption {
          type = types.str;
          default = "ci";
          description = "Environment-owned root prefix below which repository and trust namespaces are created.";
        };

        keyInputs = mkOption {
          type = types.listOf types.str;
          default = [
            "repository"
            "architecture"
            "compiler-generation"
            "cache-generation"
            "trust-tier"
          ];
          readOnly = true;
          description = "Required sccache namespace inputs.";
        };

        statisticsCommand = mkOption {
          type = types.str;
          default = "sccache --show-stats";
          readOnly = true;
          description = "Native statistics command workflows report after direct Cargo/rustc work.";
        };
      };

    config = {
      observability = [
        "sccache-statistics"
        "publication-result"
      ];
      runtimeSecretEnv = lib.mkDefault [
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
      ];
    };
  };

  pythonProfileType = types.submodule {
    options =
      profileCommon
      // {
        endpoint = mkOption {
          type = types.str;
          description = "Object-cache endpoint used by the platform transport around uv's native cache directory.";
        };

        bucket = mkOption {
          type = types.str;
          description = "Object bucket used to persist the pruned uv cache.";
        };

        region = mkOption {
          type = types.str;
          description = "Object-cache region identifier passed to the platform transport.";
        };

        keyPrefix = mkOption {
          type = types.str;
          default = "ci";
          description = "Environment-owned root prefix below which repository and trust namespaces are created.";
        };

        cacheDir = mkOption {
          type = types.str;
          default = ".ci-cache/uv";
          description = "Workspace-relative UV_CACHE_DIR; never a persistent undifferentiated home directory.";
        };

        keyInputs = mkOption {
          type = types.listOf types.str;
          default = [
            "repository"
            "platform"
            "python-abi"
            "uv-cache-generation"
            "lock-input"
            "trust-tier"
          ];
          readOnly = true;
          description = "Required uv cache identity inputs.";
        };

        pruneCommand = mkOption {
          type = types.str;
          default = "uv cache prune --ci";
          readOnly = true;
          description = "Native uv pruning command required before publication.";
        };
      };

    config = {
      observability = [
        "uv-cache-summary"
        "publication-result"
      ];
      runtimeSecretEnv = lib.mkDefault [
        "AWS_ACCESS_KEY_ID"
        "AWS_SECRET_ACCESS_KEY"
      ];
    };
  };

  availableProfiles =
    lib.optionalAttrs (cfg.profiles.nix != null) {
      nix = cfg.profiles.nix // {kind = "nix";};
    }
    // lib.optionalAttrs (cfg.profiles.rust != null) {
      rust = cfg.profiles.rust // {kind = "sccache";};
    }
    // lib.optionalAttrs (cfg.profiles.python != null) {
      python =
        cfg.profiles.python
        // {
          kind = "uv";
          transport = "s3";
        };
    };

  selectedProfiles = lib.filterAttrs (name: _: builtins.elem name cfg.requestedProfiles) availableProfiles;

  contract = {
    version = 1;
    ownership = "consumer";
    failurePolicy = "report-and-continue";
    trustPolicy = {
      pullRequestWritesOwnNamespace = true;
      protectedReadsPullRequest = false;
      directPromotion = false;
      # Pull-request Nix outputs reach only the quarantine endpoint; a
      # protected pipeline rebuilds and publishes its own closures. Nothing is
      # ever copied quarantine -> protected.
      promotion = "rebuild";
      # The quarantine is never a substituter for any tier: a lane's store is
      # shared by every pipeline on it, so unsigned pull-request outputs must
      # not be substituted into it. This isolates *publication*; it does not
      # isolate a pull request's builds from the shared lane store itself.
      quarantineSubstitution = false;
      inherit credentialEnvPrefixes;
    };
    profiles = selectedProfiles;
  };
in {
  options.agentic.ciCache = {
    requestedProfiles = mkOption {
      type = types.listOf (types.enum [
        "nix"
        "rust"
        "python"
      ]);
      default = [];
      apply = lib.unique;
      description = "Cache ecosystems requested by the repository. Only profiles supplied by an environment layer enter the contract.";
    };

    profiles = {
      nix = mkOption {
        type = types.nullOr nixProfileType;
        default = null;
        description = "Environment-provided signed substituters plus trust-tiered completed-closure publication endpoints.";
      };

      rust = mkOption {
        type = types.nullOr rustProfileType;
        default = null;
        description = "Environment-provided direct Cargo/rustc sccache contract.";
      };

      python = mkOption {
        type = types.nullOr pythonProfileType;
        default = null;
        description = "Environment-provided Python/uv cache contract.";
      };
    };

    lib = mkOption {
      type = types.raw;
      readOnly = true;
      description = "Resolved contract (`contract`, JSON-serializable), its store file (`contractFile pkgs`), and the pre-wired client (`tools pkgs`).";
    };
  };

  config = {
    agentic.ciCache.lib = {
      inherit contract;
      # Store path of the contract JSON (public metadata only).
      contractFile = pkgs: tool.contractFile pkgs contract;
      # `agentic-ci-cache` with this contract pre-wired; the same binary is
      # published standalone as packages.<system>.ci-cache for consumers that
      # do not import the flake module.
      tools = pkgs: tool.mkWrappedTool pkgs (tool.mkTool pkgs) (tool.contractFile pkgs contract);
    };
    flake.agenticCiCacheContract = contract;
  };
}
