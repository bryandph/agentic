import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFileSync } from "node:child_process";

export const schema = "agentic.seat-snapshot/1";
const segment = (s) => typeof s === "string" && /^[A-Za-z0-9_.-]+$/.test(s) && s !== "." && s !== "..";

// Dependency injection is for fixtures/future supported diagnostics providers.
// Production never reads Cotal's private process-global runtime map.
export function createWriter({ env = process.env, pid = process.pid, now = Date.now,
  readConnection = () => { throw new Error("observation unavailable: connector has no supported diagnostics API (cotal unknown)"); },
} = {}) {
  const { COTAL_SPACE: space, COTAL_NAME: name } = env;
  if (!segment(space) || !segment(name)) return null;
  const dir = path.join(env.XDG_STATE_HOME || path.join(env.HOME || os.homedir(), ".local/state"), "cotal-seat", space);
  const file = path.join(dir, `${name}.json`);
  const temporary = `${file}.tmp.${pid}`;
  return {
    file,
    write(context) {
      let connection = null, connectionError = null;
      try { connection = readConnection(); } catch (error) { connectionError = String(error.message).slice(0, 240); }
      const snapshot = { schema, space, name, instanceId: env.COTAL_ID || null, pid,
        piSession: context.sessionManager.getSessionFile() || null, cwd: context.cwd,
        writtenAt: now(), connection, connectionError };
      fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
      fs.chmodSync(path.dirname(dir), 0o700);
      fs.chmodSync(dir, 0o700);
      let fd;
      try {
        fd = fs.openSync(temporary, "wx", 0o600);
        fs.writeFileSync(fd, `${JSON.stringify(snapshot)}\n`);
        fs.fsyncSync(fd);
        fs.closeSync(fd); fd = undefined;
        fs.renameSync(temporary, file);
      } finally {
        if (fd !== undefined) fs.closeSync(fd);
        fs.rmSync(temporary, { force: true });
      }
      return snapshot;
    },
    remove() {
      // Do not unlink another incarnation's file if the identity was reused.
      try { if (JSON.parse(fs.readFileSync(file, "utf8")).pid === pid) fs.unlinkSync(file); }
      catch (error) { if (error.code !== "ENOENT") throw error; }
    },
  };
}

export default function (pi) {
  let writer, timer;
  pi.on("session_start", (_event, context) => {
    let version = "unknown";
    try { version = JSON.parse(execFileSync("cotal", ["version", "--json"], { timeout: 3000, stdio: ["ignore", "pipe", "ignore"] })).result.version; } catch {}
    writer = createWriter({ readConnection: () => {
      throw new Error(`observation unavailable: connector has no supported diagnostics API (cotal ${version})`);
    } });
    if (!writer) return;
    const write = () => {
      try { writer.write(context); } catch (error) { console.error(`agentic-seat-snapshot: ${error.message}`); }
    };
    write();
    timer = setInterval(write, 60_000);
    timer.unref();
  });
  pi.on("session_shutdown", () => {
    clearInterval(timer);
    writer?.remove();
    writer = null;
  });
}
