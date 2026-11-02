"""Read-only seat observations; unknown schemas are never healthy."""
import argparse
import errno
import json
import math
import os
from pathlib import Path
import time

SCHEMA = "agentic.seat-snapshot/1"


def root():
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "cotal-seat"


def alive(pid):
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return None
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError as error:
        return False if error.errno == errno.ESRCH else None


def read(file):
    record = {"path": str(file), "available": False, "stale": True, "snapshot": None}
    try:
        data = json.loads(file.read_text())
        record["snapshot"] = data
        if not isinstance(data, dict) or data.get("schema") != SCHEMA:
            raise ValueError("unsupported snapshot schema")
        stamp = data.get("writtenAt")
        if not isinstance(stamp, (float, int)) or isinstance(stamp, bool) or not math.isfinite(stamp):
            raise ValueError("invalid writtenAt")
        live = alive(data.get("pid"))
        if live is None:
            raise ValueError("invalid or unobservable pid")
        record.update(available=True, pidAlive=live, ageMs=max(0, time.time() * 1000 - stamp))
        record["stale"] = record["ageMs"] > 180_000 or not live
        connection = data.get("connection")
        record["queue"] = ({k: connection.get(k) for k in (
            "state", "bufferedCount", "automaticCount", "oldestAutomaticAt",
            "automaticQueueStalledForMs", "lastDrainedAt", "lastAutomaticHeadDrainedAt")}
            if isinstance(connection, dict) else None)
        record["observationError"] = data.get("connectionError")
    except (OSError, ValueError, TypeError) as error:
        record["observationError"] = str(error)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--space")
    parser.add_argument("--name")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    records = []
    for file in sorted(root().glob("*/*.json")):
        if args.space and file.parent.name != args.space or args.name and file.stem != args.name:
            continue
        records.append(read(file))
    if args.json:
        print(json.dumps(records))
    else:
        for row in records:
            print(json.dumps(row))


if __name__ == "__main__":
    main()
