"""workspace-overrides: point a consumer flake's inputs at local checkouts.

Reads the consumer's flake.lock and the resolved workspace declaration
($WORKBENCH_WORKSPACE_MANIFEST) and prints `--override-input` arguments
for every input whose locked or original URL is a declared repository's
URL or alias, plus `--no-write-lock-file`. With `-- nix <cmd> ...` it
runs that command with the arguments added instead. Matches and skips go
to stderr; stdout carries only the argument list.
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from urllib.parse import unquote, urlsplit

PROG = "workspace-overrides"

USAGE = f"""\
{PROG} [options] [FLAKE_DIR]
{PROG} [options] [--flake FLAKE_DIR] -- nix <subcommand> [args ...]

Print --override-input arguments that point the inputs of the flake in
FLAKE_DIR (default: the current directory) at local workspace checkouts,
followed by --no-write-lock-file. Inputs match a declared repository when
their locked or original URL equals the repository's URL or an alias after
normalisation; inputs that cannot match by URL are mapped with --map or
the declaration's `workspace.overrides`. The flake.lock is never written.

With `-- nix <subcommand> ...` the command runs with the arguments
inserted directly after the subcommand (`nix build ARGS ...`,
`nix flake check ARGS ...`), so they never land after `--` or `-c`.
Supported: nix build, develop, eval, run, shell, print-dev-env, repl,
path-info, log, bundle, search, why-depends and nix flake
check, show, metadata, info, archive. Other commands are refused.
"""

EXEC_SUBCOMMANDS = {
    "build",
    "develop",
    "eval",
    "run",
    "shell",
    "print-dev-env",
    "repl",
    "path-info",
    "log",
    "bundle",
    "search",
    "why-depends",
}
EXEC_FLAKE_SUBCOMMANDS = {"check", "show", "metadata", "info", "archive"}

# Flake-reference types whose repositories live at <host>/<owner>/<repo>.
FORGE_TYPES = {"github": "github.com", "gitlab": "gitlab.com", "sourcehut": "git.sr.ht"}
# Flake-reference schemes that the scp-style `host:path` form would
# otherwise mistake for a host.
FLAKE_SCHEMES = {"path", "flake", "file", "tarball", "hg", "git", "http", "https", "ssh"}
SCP = re.compile(r"^(?:[^@/]+@)?(?P<host>[^:/]+):(?P<path>(?!//).*)$")


def warn(message):
    print(f"{PROG}: {message}", file=sys.stderr)


def fail(message, code=2):
    warn(message)
    sys.exit(code)


def canonical_path(path):
    path = unquote(path).strip("/")
    if path.endswith(".git"):
        path = path[: -len(".git")]
    return path.rstrip("/")


def normalise(url):
    """Reduce a repository URL to `host/path`, or `file:/abs/path` for a
    local repository, so that transports and spellings of one repository
    compare equal. Returns None for anything that names no repository
    (relative paths, registry ids, empty strings).

    Dropped: the `git+` prefix, the scheme, user and port, query and
    fragment, a trailing `.git` and slashes. The host is compared
    case-insensitively, the path exactly.
    """
    if not url:
        return None
    url = url.strip()
    if url.startswith("git+"):
        url = url[len("git+") :]
    if url.startswith(("github:", "gitlab:", "sourcehut:")):
        kind, rest = url.split(":", 1)
        rest = rest.split("?", 1)[0].split("#", 1)[0]
        parts = [p for p in rest.split("/") if p]
        if len(parts) < 2:
            return None
        return f"{FORGE_TYPES[kind]}/{canonical_path('/'.join(parts[:2]))}"
    if url.startswith("/"):
        return "file:" + "/" + canonical_path(url)
    if "://" in url:
        parts = urlsplit(url)
        if parts.scheme == "file":
            return "file:" + "/" + canonical_path(parts.path)
        if parts.scheme not in ("ssh", "https", "http", "git"):
            return None
        host = (parts.hostname or "").lower()
        if not host:
            return None
        path = canonical_path(parts.path)
        return f"{host}/{path}" if path else None
    m = SCP.match(url)
    if m and m.group("host") not in FLAKE_SCHEMES:
        path = m.group("path").split("?", 1)[0]
        path = canonical_path(path)
        return f"{m.group('host').lower()}/{path}" if path else None
    return None


def node_urls(ref):
    """Repository URLs a lock `locked` or `original` attrset refers to."""
    if not isinstance(ref, dict):
        return []
    kind = ref.get("type")
    if kind in FORGE_TYPES:
        if "owner" not in ref or "repo" not in ref:
            return []
        host = ref.get("host", FORGE_TYPES[kind])
        return [f"https://{host}/{ref['owner']}/{ref['repo']}"]
    if kind == "git":
        return [ref["url"]] if "url" in ref else []
    return []


def walk_lock(lock):
    """Yield (input path, node name or None, follows target or None) for
    every input reachable from the root through non-follows edges."""
    nodes = lock.get("nodes", {})
    root = nodes.get(lock.get("root", "root"), {})
    queue = [((), root)]
    while queue:
        prefix, node = queue.pop(0)
        for name, target in sorted(node.get("inputs", {}).items()):
            path = prefix + (name,)
            if isinstance(target, list):
                yield path, None, tuple(target)
                continue
            yield path, target, None
            if target in nodes:
                queue.append((path, nodes[target]))


def parse_pairs(values, flag):
    pairs = {}
    for value in values:
        key, sep, rest = value.partition("=")
        if not sep or not key or not rest:
            fail(f"{flag} expects NAME=VALUE, got {value!r}")
        pairs[key] = rest
    return pairs


def split_exec(argv):
    if "--" in argv:
        i = argv.index("--")
        return argv[:i], argv[i + 1 :]
    return argv, None


def insertion_point(command):
    """Index in `command` after the nix subcommand, or exit with a refusal."""
    supported = "nix " + ", ".join(sorted(EXEC_SUBCOMMANDS)) + "; nix flake " + ", ".join(sorted(EXEC_FLAKE_SUBCOMMANDS))
    if not command:
        fail("nothing to run after `--`")
    if os.path.basename(command[0]) != "nix":
        fail(f"refusing to run {command[0]!r}: only nix commands take --override-input ({supported})")
    if len(command) < 2 or command[1].startswith("-"):
        fail("put the nix subcommand first, as in `nix build ...`; nix options go after it")
    sub = command[1]
    if sub == "flake":
        if len(command) < 3 or command[2] not in EXEC_FLAKE_SUBCOMMANDS:
            what = command[2] if len(command) > 2 else ""
            fail(f"refusing `nix flake {what}`: it is not one of {supported}; lock-writing commands are never run")
        return 3
    if sub not in EXEC_SUBCOMMANDS:
        fail(f"refusing `nix {sub}`: it is not one of {supported}")
    return 2


def git(checkout, *args):
    return subprocess.run(["git", "-C", checkout, *args], capture_output=True, text=True)


def checkout_ref(checkout, scheme):
    if scheme == "path":
        return f"path:{checkout}"
    ref = f"git+file://{checkout}"
    if os.path.exists(os.path.join(checkout, ".gitmodules")):
        ref += "?submodules=1"
    return ref


def main(argv):
    own, command = split_exec(argv)
    parser = argparse.ArgumentParser(prog=PROG, usage=USAGE, add_help=True)
    parser.add_argument("flake_dir", nargs="?", help=argparse.SUPPRESS)
    parser.add_argument("--flake", dest="flake_opt", metavar="DIR", help="consumer flake directory (default: .)")
    parser.add_argument("--root", help="workspace root that declared paths are relative to (default: $DEVENV_ROOT)")
    parser.add_argument("--manifest", help="resolved declaration JSON (default: $WORKBENCH_WORKSPACE_MANIFEST)")
    parser.add_argument("--map", action="append", default=[], metavar="INPUT=KEY", help="override INPUT (slash-separated path) with repository KEY; wins over the declaration's workspace.overrides")
    parser.add_argument("--checkout", action="append", default=[], metavar="KEY=DIR", help="use DIR as KEY's checkout for this run, e.g. a worktree")
    parser.add_argument("--only", action="append", default=[], metavar="KEY|GROUP", help="limit overrides to these repository keys or groups (repeatable)")
    parser.add_argument("--scheme", choices=["git+file", "path"], default="git+file", help="checkout reference scheme (default: git+file, tracked files only)")
    parser.add_argument("-v", "--verbose", action="store_true", help="also report follows and unmatched inputs")
    opts = parser.parse_args(own)
    at = insertion_point(command) if command is not None else None

    flake_dir = os.path.abspath(opts.flake_opt or opts.flake_dir or ".")
    lock_path = os.path.join(flake_dir, "flake.lock")
    manifest_path = opts.manifest or os.environ.get("WORKBENCH_WORKSPACE_MANIFEST")
    if not manifest_path:
        fail("no resolved declaration: set --manifest or run inside the workspace shell ($WORKBENCH_WORKSPACE_MANIFEST)")
    root = opts.root or os.environ.get("DEVENV_ROOT")
    if not root:
        fail("no workspace root: set --root or run inside the workspace shell ($DEVENV_ROOT)")
    root = os.path.abspath(root)

    try:
        with open(manifest_path) as f:
            entries = {e["key"]: e for e in json.load(f)}
        with open(lock_path) as f:
            lock = json.load(f)
    except OSError as e:
        fail(f"cannot read {e.filename}: {e.strerror}")

    declared = {}
    overrides_path = os.environ.get("WORKBENCH_WORKSPACE_OVERRIDES")
    if overrides_path:
        with open(overrides_path) as f:
            declared = json.load(f)
    maps = {**{k: ("declaration", v) for k, v in declared.items()}, **{k: ("--map", v) for k, v in parse_pairs(opts.map, "--map").items()}}
    checkouts = parse_pairs(opts.checkout, "--checkout")
    for key in [v for _, v in maps.values()] + list(checkouts):
        if key not in entries:
            fail(f"unknown repository key {key!r}; declared: {', '.join(sorted(entries)) or 'none'}")
    if opts.only:
        known = set(entries) | {g for e in entries.values() for g in e["groups"]}
        for sel in opts.only:
            if sel not in known:
                fail(f"--only {sel!r} names no declared repository or group")

    def selected(key):
        e = entries[key]
        return not opts.only or key in opts.only or any(g in opts.only for g in e["groups"])

    identities = {}
    for key, e in entries.items():
        for url in [e["url"], *e["aliases"]]:
            ident = normalise(url)
            if ident:
                identities.setdefault(ident, set()).add(key)

    args = []
    overridden = set()
    reminded = set()
    follows = []
    lock_paths = set()
    for path, node_name, target in walk_lock(lock):
        name = "/".join(path)
        lock_paths.add(name)
        if name in maps:
            how, key = maps[name]
            reason = f"mapped by {how}"
        elif target is not None:
            follows.append((name, "/".join(target)))
            continue
        else:
            node = lock["nodes"].get(node_name, {})
            matches = {}
            for side in ("locked", "original"):
                for url in node_urls(node.get(side)):
                    for key in identities.get(normalise(url), ()):
                        matches.setdefault(key, url)
            if not matches:
                if opts.verbose:
                    warn(f"skip {name}: no declared repository matches")
                continue
            if len(matches) > 1:
                warn(f"skip {name}: ambiguous, matches {', '.join(sorted(matches))}; use --map {name}=<key>")
                continue
            key, url = next(iter(matches.items()))
            reason = f"url {url}"
        if not selected(key):
            if opts.verbose:
                warn(f"skip {name}: {key} not selected by --only")
            continue
        checkout = os.path.abspath(checkouts.get(key) or os.path.join(root, entries[key]["path"]))
        if not os.path.isdir(checkout):
            warn(f"skip {name}: matched {key} ({reason}) but checkout {checkout} does not exist")
            continue
        if opts.scheme == "git+file":
            if git(checkout, "rev-parse", "--git-dir").returncode != 0:
                warn(f"skip {name}: matched {key} but {checkout} is not a git checkout; try --scheme path")
                continue
            untracked = git(checkout, "ls-files", "--others", "--exclude-standard").stdout.split()
            if untracked and checkout not in reminded:
                reminded.add(checkout)
                warn(f"note: {checkout} has {len(untracked)} untracked file(s) Nix will not see; `git add -N <file>` them or use --scheme path")
        ref = checkout_ref(checkout, opts.scheme)
        warn(f"override {name} -> {key} at {ref} ({reason})")
        args += ["--override-input", name, ref]
        overridden.add(name)

    for name in maps:
        if name not in lock_paths:
            warn(f"skip {name}: mapped, but {lock_path} has no such input")
    for name, target in follows:
        if target in overridden:
            warn(f"{name} follows {target} and picks up its override")
        elif opts.verbose:
            warn(f"skip {name}: follows {target}")
    args.append("--no-write-lock-file")

    if command is None:
        print(shlex.join(args))
        return 0
    full = command[:at] + args + command[at:]
    warn("running " + shlex.join(full))
    os.execvp(full[0], full)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
