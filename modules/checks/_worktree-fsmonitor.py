"""Exercise setup with real linked Git worktrees; fake only daemon and Nix."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

setup = sys.argv[1]
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    env = dict(os.environ, HOME=tmp, GIT_CONFIG_NOSYSTEM="1",
               GIT_CONFIG_GLOBAL=str(root / "global"))

    def git(*args):
        return subprocess.check_output(["git", *map(str, args)], env=env, text=True, timeout=15).strip()

    git("config", "--global", "user.name", "fixture")
    git("config", "--global", "user.email", "fixture@example.invalid")
    git("config", "--global", "core.fsmonitor", "false")
    git("config", "--global", "core.untrackedCache", "true")
    main, linked = root / "main", root / "linked"
    git("init", "-q", main)
    git("-C", main, "-c", "core.fsmonitor=false", "commit", "-qm", "init", "--allow-empty")
    git("-C", main, "worktree", "add", "-q", "--detach", linked)
    git("config", "--global", "core.fsmonitor", "true")
    gitdir = Path(git("-C", linked, "rev-parse", "--absolute-git-dir"))
    common = main / ".git"
    ipc = gitdir / "fsmonitor--daemon.ipc"
    log, state = root / "daemon-log", root / "daemon-state"
    bindir = root / "bin"
    bindir.mkdir()
    nix = bindir / "nix"
    nix.write_text(f'#!{sys.argv[2]}\ntest ! -e "$DAEMON_SOCKET"\n')
    nix.chmod(0o755)
    env.update(PATH=str(bindir) + ":" + env["PATH"], DAEMON_LOG=str(log),
               DAEMON_SOCKET=str(ipc), DAEMON_STATE=str(state))
    subprocess.run([str(nix), "flake", "metadata", "--json"], env=env, check=True)
    global_before = (root / "global").read_bytes()
    main_before = (common / "config").read_bytes()

    def run(path, mode, success=True):
        env["DAEMON_MODE"] = mode
        result = subprocess.run([setup, "--worktree", str(path)], env=env,
                                capture_output=True, text=True, timeout=15)
        assert (result.returncode == 0) == success, result.stderr
        return result

    # A main checkout must never get a pin or any daemon calls.
    run(main, "running")
    assert (common / "config").read_bytes() == main_before
    assert not (common / "config.worktree").exists()
    assert not log.exists()
    # Use an actual Unix socket: existence checks must not require a plain file.
    with socket.socket(socket.AF_UNIX) as sock:
        os.chdir(gitdir)
        sock.bind(ipc.name)
        os.chdir(root)
        run(linked, "running")
        assert not ipc.exists()
    assert state.read_text().strip() == "stopped"
    assert log.read_text().splitlines() == [f"-C {linked} fsmonitor--daemon status",
                                           f"-C {linked} fsmonitor--daemon stop"]
    assert git("-C", linked, "config", "core.fsmonitor") == "false"
    assert git("-C", main, "config", "core.fsmonitor") == "true"
    assert git("-C", linked, "config", "core.untrackedCache") == "true"
    assert git("config", "--file", gitdir / "config.worktree", "core.fsmonitor") == "false"
    assert git("config", "--file", common / "config", "extensions.worktreeConfig") == "true"
    config_before = (gitdir / "config.worktree").read_bytes()
    common_before = (common / "config").read_bytes()
    for mode in ["stopped", "missing", "stopped"]:
        log.write_text("")
        run(linked, mode)
        assert log.read_text().splitlines() == [f"-C {linked} fsmonitor--daemon status"]
        assert (gitdir / "config.worktree").read_bytes() == config_before
        assert (common / "config").read_bytes() == common_before
    # A successful stop which leaves IPC behind fails closed before Nix.
    with socket.socket(socket.AF_UNIX) as sock:
        os.chdir(gitdir)
        sock.bind(ipc.name)
        os.chdir(root)
        failure = run(linked, "remains", success=False)
        assert "setup failed at fsmonitor" in failure.stderr
        assert str(ipc) in failure.stderr
        record = json.loads((gitdir / "workbench-setup.json").read_text())
        assert record["failedStep"] == "fsmonitor" and record["status"] == "failed"
        assert ipc.exists(), "setup must not unlink IPC itself"
    ipc.unlink()  # Only this fixture-owned socket, never product behavior.
    run(linked, "stopped")
    assert (root / "global").read_bytes() == global_before
    print("main untouched; linked pin false; running/stopped/missing/remains; idempotent")
