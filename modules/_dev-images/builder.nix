# Workbench dev-environment images (OpenSpec `distributable-dev-environments`,
# BPH-39): one image family for devcontainers (VS Code, Cursor) and OpenShell
# sandboxes, built with nix2container on a digest-pinned buildpack-deps:noble
# base.
#
#   mkDevImage { name, withNix?, network?, substituters?, extraCA?,
#                nixFetchHosts?, extraPackages?, warmPaths?, tag? }
#     dev-base shape by default; withNix adds single-user Nix and devenv with
#     the image closure registered; warmPaths bakes a repository's devShell
#     environment (per-repository warm images).
#
# A function of the instantiator's `pkgs`, so a consumer's overlays and pins
# apply and its images stay byte-identical across the extraction. Core
# defaults reference public endpoints only; private caches, CAs and forges
# are parameters.
{
  pkgs,
  lib,
  # nix2container's flake packages for this system (nix2container,
  # skopeo-nix2container).
  nix2container,
  # Agent harness packages, shipped unconfigured: { claude-code, codex, pi }.
  harnesses,
}: let
  account = "sandbox";
  uid = 1000;
  home = "/sandbox";

  # buildpack-deps:noble (Docker official: ubuntu:24.04 plus build-essential
  # and common -dev libraries, so sdists with C extensions build against
  # the same glibc the FHS Python uses), per-architecture manifests pinned
  # by digest. Refresh:
  #   skopeo inspect --raw docker://docker.io/library/buildpack-deps:noble
  base =
    {
      x86_64-linux = nix2container.nix2container.pullImage {
        imageName = "docker.io/library/buildpack-deps";
        imageDigest = "sha256:f0b8901ade1e5b1ba6b23593cbc235ebf9b98393fc7a6448a29c1f863939c5bc";
        arch = "amd64";
        sha256 = "sha256-S4VpXWdq8Dmm359fDdvvky2fSvCzcRm/LWdBOHZMP8E=";
      };
      aarch64-linux = nix2container.nix2container.pullImage {
        imageName = "docker.io/library/buildpack-deps";
        imageDigest = "sha256:9449bf7e77fb32a0f29c42ff8e1c1adb15b2eb6c7726bec1c45c0f01c0a80c84";
        arch = "arm64";
        sha256 = "sha256-9iwhVX88EzXgcNEVvHsLgUudRMgNFv39d9OqKCfn9HU=";
      };
    }
    .${
      pkgs.stdenv.hostPlatform.system
    };

  # Toolchains and CLIs (design D2). Harnesses are the pinned llm-agents
  # builds, unwrapped and unconfigured: credentials only ever arrive through
  # OpenShell providers or the user's own environment.
  toolchains = with pkgs; [
    go
    uv
    ansible
    ansible-lint
    opentofu
    kubectl
    kubernetes-helm
    git
    gh
    just
    mise
    ripgrep
    fd
    jq
    curl
    # OpenShell's bring-your-own-container contract.
    iproute2
  ];
  harnessList = lib.attrValues harnesses;

  # The `python3` on PATH is uv's managed CPython (python-build-standalone),
  # not nixpkgs': a Nix interpreter does not search the FHS library paths, so
  # manylinux wheels with native code (numpy, ...) fail to load
  # (libstdc++.so.6). It is baked where uv looks by default ($HOME), so
  # OpenShell's /sandbox seeding carries it. Nix-built tools (ansible) keep
  # their own interpreter. Refresh: `uv python list --show-urls`.
  pythonVersion = "3.13.14";
  pythonBuild = "20260610";
  pythonArch = pkgs.stdenv.hostPlatform.parsed.cpu.name;
  pythonDir = "${home}/.local/share/uv/python/cpython-${pythonVersion}-linux-${pythonArch}-gnu";
  # Unpacked into the image root (one copyToRoot source, so /sandbox has a
  # single ownership rule).
  pythonSrc = pkgs.fetchurl {
    url = "https://releases.astral.sh/github/python-build-standalone/releases/download/${pythonBuild}/cpython-${pythonVersion}%2B${pythonBuild}-${pythonArch}-unknown-linux-gnu-install_only_stripped.tar.gz";
    hash =
      {
        aarch64 = "sha256-b0UDAlWSjSEP4pY6dpxTufmYJ3eVV9EX0rlzMq0G+UM=";
        x86_64 = "sha256-1gfhjoMiegUnzz9UpIvpc6dTWKaIXkvmfUsDWbbxyIA=";
      }
      .${
        pythonArch
      };
  };
  nixTools = with pkgs; [nix devenv direnv nix-direnv];

  # Warm-image builder/publisher (design D9); also an app.
  devImageRepo = pkgs.writeShellApplication {
    name = "dev-image-repo";
    runtimeInputs = [
      nix2container.skopeo-nix2container
      pkgs.crane
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
      pkgs.findutils
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ./dev-image-repo.sh;
  };

  # Worker evidence runner (design D7).
  devVerify = pkgs.writeShellApplication {
    name = "dev-verify";
    runtimeInputs = with pkgs; [bash coreutils git jq];
    text = builtins.readFile ./dev-verify.sh;
  };

  # Egress groups for the image policy, each bound to the binaries that use
  # them (the supervisor enforces binary identity on resolved store paths).
  rule = name: hosts: packages: {
    inherit name;
    endpoints =
      map (host: {
        inherit host;
        port = 443;
        protocol = "rest";
        enforcement = "enforce";
        access = "full";
      })
      hosts;
    binaries = map (p: {path = "${p}/**";}) packages;
  };
  github = ["github.com" "api.github.com" "codeload.github.com" "objects.githubusercontent.com" "release-assets.githubusercontent.com"];
  baseNetwork = {
    go = rule "go" ["proxy.golang.org" "sum.golang.org" "storage.googleapis.com"] [pkgs.go];
    python =
      rule "python" ["pypi.org" "files.pythonhosted.org"] [pkgs.uv]
      // {binaries = [{path = "${pkgs.uv}/**";} {path = "${pythonDir}/**";}];};
    galaxy = rule "galaxy" ["galaxy.ansible.com"] [pkgs.python3];
    opentofu = rule "opentofu" (["registry.opentofu.org"] ++ github) [pkgs.opentofu];
    git = rule "git" github [pkgs.git pkgs.gh];
    anthropic = rule "anthropic" ["api.anthropic.com" "claude.ai" "console.anthropic.com" "platform.claude.com"] [harnesses.claude-code harnesses.pi];
    openai = rule "openai" ["api.openai.com" "auth.openai.com" "chatgpt.com" "ab.chatgpt.com"] [harnesses.codex harnesses.pi];
  };

  publicSubstituters = {
    "https://cache.nixos.org" = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
    "https://devenv.cachix.org" = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
  };

  # Account files: the base image's own entries with its `ubuntu` user
  # (uid 1000) replaced by `sandbox`. Copied from the pinned base; refresh
  # them with the digests above.
  systemUsers = ''
    root:x:0:0:root:/root:/bin/bash
    daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
    bin:x:2:2:bin:/bin:/usr/sbin/nologin
    sys:x:3:3:sys:/dev:/usr/sbin/nologin
    sync:x:4:65534:sync:/bin:/bin/sync
    games:x:5:60:games:/usr/games:/usr/sbin/nologin
    man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
    lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin
    mail:x:8:8:mail:/var/mail:/usr/sbin/nologin
    news:x:9:9:news:/var/spool/news:/usr/sbin/nologin
    uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin
    proxy:x:13:13:proxy:/bin:/usr/sbin/nologin
    www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
    backup:x:34:34:backup:/var/backups:/usr/sbin/nologin
    list:x:38:38:Mailing List Manager:/var/list:/usr/sbin/nologin
    irc:x:39:39:ircd:/run/ircd:/usr/sbin/nologin
    _apt:x:42:65534::/nonexistent:/usr/sbin/nologin
    nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
    ${account}:x:${toString uid}:${toString uid}::${home}:/bin/bash
  '';
  systemGroupNames = [
    "root:0"
    "daemon:1"
    "bin:2"
    "sys:3"
    "adm:4"
    "tty:5"
    "disk:6"
    "lp:7"
    "mail:8"
    "news:9"
    "uucp:10"
    "man:12"
    "proxy:13"
    "kmem:15"
    "dialout:20"
    "fax:21"
    "voice:22"
    "cdrom:24"
    "floppy:25"
    "tape:26"
    "sudo:27"
    "audio:29"
    "dip:30"
    "www-data:33"
    "backup:34"
    "operator:37"
    "list:38"
    "irc:39"
    "src:40"
    "shadow:42"
    "utmp:43"
    "video:44"
    "sasl:45"
    "plugdev:46"
    "staff:50"
    "games:60"
    "users:100"
    "nogroup:65534"
    "_ssh:101"
    "${account}:${toString uid}"
  ];
  groupName = entry: lib.head (lib.splitString ":" entry);
  userNames = map (l: lib.head (lib.splitString ":" l)) (lib.filter (l: l != "") (lib.splitString "\n" systemUsers));

  mkDevImage = {
    name,
    tag ? null,
    extraPackages ? [],
    withNix ? false,
    substituters ? publicSubstituters,
    network ? {},
    # Extra PEM trust appended to the Mozilla bundle (the internal CA for
    # the private instantiation).
    extraCA ? null,
    fromImage ? base,
    # Store paths baked as a warm environment (per-repository images, design
    # D9): registered in the Nix database and GC-rooted, in their own layers.
    warmPaths ? [],
    # Extra hosts Nix may fetch flake inputs from (the private forge).
    nixFetchHosts ? [],
    # A derivation whose contents are merged into the image root (for example
    # a personal Home Manager generation under the home directory). Merged
    # into the single root source so /sandbox keeps one ownership rule; its
    # store references are registered with the rest of the closure.
    extraRoot ? null,
    # Directories placed in front of PATH (for example a profile whose
    # wrappers shadow the image's unconfigured harnesses).
    pathPrefix ? [],
  }: let
    caBundle =
      if extraCA == null
      then "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      else
        pkgs.runCommand "${baseNameOf name}-ca-bundle.crt" {} ''
          cat ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt ${extraCA} > $out
        '';

    tools = pkgs.buildEnv {
      name = "${baseNameOf name}-tools";
      paths = toolchains ++ harnessList ++ [devVerify] ++ lib.optionals withNix nixTools ++ extraPackages;
      pathsToLink = ["/bin" "/share/nix-direnv"];
    };

    policySpec = {
      version = 1;
      filesystem_policy = {
        include_workdir = true;
        read_only =
          ["/bin" "/sbin" "/usr" "/lib" "/lib64" "/etc" "/proc" "/dev/urandom" "/var/log" "/sys/fs/cgroup"]
          ++ lib.optional (!withNix) "/nix/store";
        # /dev/shm: Python multiprocessing semaphores (pre-commit hooks,
        # ansible). Nix allocates a pty for every build. (Read-only
        # /sys/fs/cgroup above: tools such as ansible-lint size their pools
        # from cpu.max.)
        read_write = ["/sandbox" "/tmp" "/var/tmp" "/dev/null" "/dev/shm"] ++ lib.optionals withNix ["/nix" "/dev/ptmx" "/dev/pts"];
      };
      landlock.compatibility = "best_effort";
      network_policies =
        baseNetwork
        // network
        // lib.optionalAttrs withNix {
          # Substituters, plus what flake evaluation fetches: the flake
          # registry and input sources (GitHub tarballs, the forge).
          nix = rule "nix" (map (u: lib.removePrefix "https://" u) (lib.attrNames substituters) ++ ["channels.nixos.org" "releases.nixos.org"] ++ github ++ nixFetchHosts) [pkgs.nix pkgs.devenv];
        };
    };

    # The supervisor checks the resolved executable path, and wrapper or
    # meta packages (pkgs.nix's bin/nix links into its CLI component) resolve
    # elsewhere. For every bound package, also bind the store roots its
    # bin/* executables resolve to. JSON is valid YAML.
    policy =
      pkgs.runCommand "${baseNameOf name}-policy.yaml" {
        spec = builtins.toJSON policySpec;
        passAsFile = ["spec"];
        nativeBuildInputs = [pkgs.jq];
      } ''
        roots='{}'
        for bound in $(jq -r '[.network_policies[].binaries[].path | rtrimstr("/**")] | unique[]' "$specPath"); do
          [ -d "$bound/bin" ] || continue
          for exe in "$bound"/bin/*; do
            root=$(readlink -f "$exe" | cut -d/ -f1-4)
            [ "$root" = "$bound" ] && continue
            roots=$(jq -c --arg b "$bound" --arg r "$root" '.[$b] = ((.[$b] // []) + [$r] | unique)' <<< "$roots")
          done
        done
        jq --argjson roots "$roots" '
          .network_policies |= map_values(.binaries |= (
            . + [.[].path | rtrimstr("/**") | ($roots[.] // [])[] | {path: (. + "/**")}] | unique_by(.path)))
        ' "$specPath" > $out
      '';

    nixConf = pkgs.writeText "nix.conf" ''
      experimental-features = nix-command flakes
      # OpenShell is the isolation boundary; Nix's build sandbox cannot nest,
      # and the supervisor refuses a nested seccomp filter ("unable to load
      # seccomp BPF program: Operation not permitted").
      sandbox = false
      filter-syscalls = false
      substituters = ${lib.concatStringsSep " " (lib.attrNames substituters)}
      trusted-public-keys = ${lib.concatStringsSep " " (lib.attrValues substituters)}
      builders =
    '';

    # The non-store part of the root filesystem.
    root = pkgs.runCommand "${baseNameOf name}-root" {} ''
      mkdir -p $out/usr/local/bin $out/etc/ssl/certs $out/etc/openshell $out/etc/profile.d $out${home}
      for f in ${tools}/bin/*; do ln -s "$f" "$out/usr/local/bin/$(basename "$f")"; done
      mkdir -p $out${pythonDir}
      tar -xzf ${pythonSrc} -C $out${pythonDir} --strip-components=1
      for f in python3 python python${lib.versions.majorMinor pythonVersion} pip3 pip; do
        ln -sf ${pythonDir}/bin/$f $out/usr/local/bin/$f
      done

      cat > $out/etc/passwd <<'EOF'
      ${systemUsers}EOF
      cat > $out/etc/group <<'EOF'
      ${lib.concatMapStrings (g: "${groupName g}:x:${lib.last (lib.splitString ":" g)}:\n") systemGroupNames}EOF
      ${lib.concatMapStrings (u: "echo '${u}:*:19000:0:99999:7:::' >> $out/etc/shadow\n") (lib.remove account userNames)}
      echo '${account}:!:19000:0:99999:7:::' >> $out/etc/shadow
      ${lib.concatMapStrings (g: "echo '${groupName g}:*::' >> $out/etc/gshadow\n") (lib.remove "${account}:${toString uid}" systemGroupNames)}
      echo '${account}:!::' >> $out/etc/gshadow

      # Nix-built clients look here; SSL_CERT_FILE is left to the OpenShell
      # supervisor, which terminates TLS with its own ephemeral CA.
      ln -s ${caBundle} $out/etc/ssl/certs/ca-certificates.crt
      install -m 0644 ${policy} $out/etc/openshell/policy.yaml
      ${lib.optionalString withNix ''
        mkdir -p $out/etc/nix
        install -m 0644 ${nixConf} $out/etc/nix/nix.conf
        cat > $out/etc/profile.d/nix-direnv.sh <<'EOF'
        # direnv + nix-direnv for interactive shells; devenv and `use flake`
        # then reuse the image's registered store paths.
        [ -n "$BASH_VERSION" ] && command -v direnv >/dev/null && eval "$(direnv hook bash)"
        EOF
        mkdir -p $out${home}/.config/direnv
        echo 'source ${tools}/share/nix-direnv/direnvrc' > $out${home}/.config/direnv/direnvrc
      ''}${lib.optionalString (extraRoot != null) ''
        cp -rP --no-preserve=mode --remove-destination ${extraRoot}/. $out/
        chmod -R u+w $out
      ''}
    '';
    # GC roots for the warm paths. A separate source whose permissions match
    # nix2container's database layer exactly: /nix/var/nix appears in both,
    # and nix2container refuses a path carrying two different rule sets.
    warmRoots =
      pkgs.runCommand "${baseNameOf name}-warm-roots" {} ''
        mkdir -p $out/nix/var/nix/gcroots/dev-env
        ${lib.concatImapStrings (i: p: "ln -s ${p} $out/nix/var/nix/gcroots/dev-env/${toString i}
") warmPaths}
      '';

    # Large, stable layers first; identical inputs give byte-identical
    # layers, so dev-nix and every warm image share them.
    baseLayers = [
      (nix2container.nix2container.buildLayer {deps = toolchains;})
      (nix2container.nix2container.buildLayer {deps = harnessList;})
    ];
  in
    assert lib.assertMsg (warmPaths == [] || withNix) "dev-images: warmPaths need withNix";
      nix2container.nix2container.buildImage {
        inherit name tag fromImage;
        copyToRoot = [root] ++ lib.optional (warmPaths != []) warmRoots;
        layers =
          baseLayers
          ++ lib.optional (warmPaths != []) (nix2container.nix2container.buildLayer {
            deps = warmPaths;
            layers = baseLayers;
            # One layer per large store path, so an environment update
            # re-pulls only what changed.
            maxLayers = 80;
          });
        maxLayers = 40;
        initializeNixDatabase = withNix;
        nixUid =
          if withNix
          then uid
          else 0;
        nixGid =
          if withNix
          then uid
          else 0;
        perms =
          lib.optional (warmPaths != []) {
            path = warmRoots;
            regex = ".*";
            mode = "0755";
            inherit uid;
            gid = uid;
          }
          ++ [
            {
              path = root;
              regex = "${home}(/.*)?$";
              mode = "0755";
              inherit uid;
              gid = uid;
              uname = account;
              gname = account;
            }
            {
              path = root;
              regex = "/etc/g?shadow$";
              mode = "0640";
            }
          ];
        config = {
          User = "${toString uid}:${toString uid}";
          WorkingDir = home;
          Env = [
            "PATH=${lib.concatMapStrings (d: d + ":") pathPrefix}/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"
            "HOME=${home}"
            "LANG=C.UTF-8"
            # uv uses the baked CPython rather than downloading or picking a
            # Nix interpreter.
            "UV_PYTHON_PREFERENCE=only-managed"
            # The base image's compiler. python-build-standalone's sysconfig
            # names clang (uv rewrites that only when it installs a Python
            # itself); setuptools derives LDSHARED from CC.
            "CC=cc"
            "CXX=c++"
          ];
        };
      }
      # The generated (non-store) root, for the shared-image check.
      // {devRoot = root;};

  # Fails when the image's generated root or manifest mentions any of the
  # given strings (an instantiator's identity and private endpoints).
  sharedImageCheck = {
    image,
    forbidden,
  }:
    pkgs.runCommand "${image.name}-shared-check" {} ''
      if grep -rIlE ${lib.escapeShellArg (lib.concatStringsSep "|" (map lib.escapeRegex forbidden))} \
        ${image.devRoot} ${image}; then
        echo "shared image ${image.name} references forbidden strings" >&2
        exit 1
      fi
      touch $out
    '';

  # Publish one image package as a digest-pinned multi-arch OCI index.
  devImagePublish = pkgs.writeShellApplication {
    name = "dev-image-publish";
    runtimeInputs = [
      nix2container.skopeo-nix2container
      pkgs.crane
      pkgs.git
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ./dev-image-publish.sh;
  };
in {
  inherit mkDevImage sharedImageCheck rule github publicSubstituters devVerify devImageRepo devImagePublish;
}
