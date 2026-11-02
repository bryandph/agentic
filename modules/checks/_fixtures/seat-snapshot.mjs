import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
const { createWriter, default: extension } = await import(process.argv[2]);
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "seat-snapshot-"));
try {
  const env = { XDG_STATE_HOME: temp, COTAL_SPACE: "fixture", COTAL_NAME: "worker-1", COTAL_ID: "local.test" };
  const context = { cwd: temp, sessionManager: { getSessionFile: () => "/session.jsonl" } };
  const connection = {state:"ready", connected:true, transportConnected:true, bufferedCount:0,
    automaticCount:0, oldestAutomaticAt:null, automaticQueueStalledForMs:0,
    lastDrainedAt:null, lastAutomaticHeadDrainedAt:null};
  const writer = createWriter({env, now: () => 1234, readConnection: () => connection});
  const snapshot = writer.write(context);
  assert.deepEqual(Object.keys(snapshot), ["schema", "space", "name", "instanceId", "pid", "piSession", "cwd", "writtenAt", "connection", "connectionError"]);
  assert.equal(snapshot.schema, "agentic.seat-snapshot/1");
  assert.equal(snapshot.writtenAt, 1234);
  assert.deepEqual(snapshot.connection, connection);
  assert.equal(snapshot.connectionError, null);
  assert.equal(fs.statSync(writer.file).mode & 0o777, 0o600);
  assert.equal(fs.statSync(path.dirname(writer.file)).mode & 0o777, 0o700);
  const old = fs.readFileSync(writer.file, "utf8");
  // Collision/failure before rename preserves the previous complete file.
  fs.writeFileSync(`${writer.file}.tmp.${process.pid}`, "collision", {mode:0o600});
  assert.throws(() => writer.write(context));
  assert.equal(fs.readFileSync(writer.file, "utf8"), old);
  writer.write(context);
  assert.equal(fs.readdirSync(path.dirname(writer.file)).length, 1);
  writer.remove(); writer.remove();
  assert.equal(fs.existsSync(writer.file), false);
  assert.equal(createWriter({env:{...env,COTAL_NAME:"../../escape"}}), null);
  const noState = createWriter({env});
  const unavailable = noState.write({...context,sessionManager:{getSessionFile:()=>undefined}});
  assert.equal(unavailable.connection, null);
  assert.match(unavailable.connectionError, /no supported diagnostics API/);
  assert.equal(unavailable.piSession, null);
  noState.remove();
  // Real extension lifecycle, with no connector/model; timer is independent of turns.
  Object.assign(process.env, env);
  const hooks = {};
  const originalInterval = globalThis.setInterval;
  const originalClear = globalThis.clearInterval;
  let tick, unref = false, cleared = false;
  globalThis.setInterval = (fn, ms) => { assert.equal(ms, 60000); tick=fn; return {unref(){unref=true;}}; };
  globalThis.clearInterval = () => { cleared=true; };
  try {
    extension({on:(event,fn)=>{hooks[event]=fn;}});
    hooks.session_start({},context);
    assert.ok(fs.existsSync(writer.file));
    assert.ok(unref);
    tick();
    hooks.session_shutdown();
    assert.ok(cleared);
    assert.equal(fs.existsSync(writer.file),false);
  } finally { globalThis.setInterval=originalInterval; globalThis.clearInterval=originalClear; }
  console.log("seat-snapshot: schema, atomic rename/failure, permissions, null observation, 60s timer, shutdown PASS");
} finally { fs.rmSync(temp,{recursive:true,force:true}); }
