"""Remove only this linked gitdir's stale fsmonitor socket, never a listener."""
import errno
import os
from pathlib import Path
import socket
import stat
import sys

path = Path(sys.argv[1])
# A relative connect avoids sockaddr_un path-length limits in deep worktrees.
os.chdir(path.parent)
name = path.name
try:
    before = os.lstat(name)
except FileNotFoundError:
    sys.exit(0)


def fail(reason):
    sys.exit(f"fsmonitor socket {path}: {reason}")


if not stat.S_ISSOCK(before.st_mode):
    fail("not a socket; refusing to remove")
with socket.socket(socket.AF_UNIX) as probe:
    probe.settimeout(0.5)
    try:
        probe.connect(name)
    except OSError as error:
        if error.errno not in (errno.ECONNREFUSED, errno.ENOENT):
            fail(f"cannot establish absence of listener: {error}")
    else:
        fail("listener present; refusing to remove")
try:
    after = os.lstat(name)
except FileNotFoundError:
    sys.exit(0)
if not stat.S_ISSOCK(after.st_mode) or (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
    fail("socket changed during probe; refusing to remove")
os.unlink(name)
print(f"removed stale fsmonitor socket {path} (no listener)", file=sys.stderr)
print(path)
if os.path.lexists(name):
    fail("remains after stale socket removal")
