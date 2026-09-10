// Real upstream adapter and real Pi tool/event APIs, with a retained extension
// instance. Only the incoming session context is supplied by this fixture.
import assert from 'node:assert/strict';
import {existsSync, readFileSync, writeFileSync} from 'node:fs';
import agenticMcp from '@adapter@/agentic.ts';

export default function(pi) {
  const handlers = new Map<string, Function[]>();
  const tools = new Map<string, any>();
  const retainedPi = new Proxy(pi, {
    get(target, key) {
      if (key === 'on') return (name, handler) => {
        handlers.set(name, [...(handlers.get(name) ?? []), handler]);
      };
      if (key === 'registerTool') return tool => {
        tools.set(tool.name, tool);
        return target.registerTool(tool);
      };
      return Reflect.get(target, key);
    },
  });
  agenticMcp(retainedPi);
  pi.on('session_start', async (_event, original) => {
    const sequence = JSON.parse(process.env.MCP_FIXTURE_SEQUENCE!);
    const reports = [];
    const events = () => existsSync(process.env.MCP_FIXTURE_EVENTS!)
      ? readFileSync(process.env.MCP_FIXTURE_EVENTS!, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line)) : [];
    const assertStopped = (prior) => {
      for (const {pid} of prior) {
        assert.throws(() => process.kill(pid, 0), {code:'ESRCH'}, 'previous session server still alive');
      }
    };
    for (const [index, {cwd, trusted}] of sequence.entries()) {
      const ctx = new Proxy(original, {get(target, key) {
        if (key === 'cwd') return cwd;
        // Bare MCP directories get true from Pi; the real trust store is the
        // extra authorization gate under test (including explicit denial).
        if (key === 'isProjectTrusted') return () => true;
        return Reflect.get(target, key);
      }});
      const prior = events();
      let resolve;
      const ready = new Promise(r => {resolve = r;});
      const off = pi.events.on('pi-mcp-adapter/status/v1', value => {
        if (value.servers.length) resolve(value);
      });
      const timer = setTimeout(() => resolve({timeout: true}), 12000);
      try {
        // Alternate explicit shutdown/start with start alone: SDK hosts can
        // retain an instance and upstream itself promises restart cleanup.
        if (index % 2) for (const shutdown of handlers.get('session_shutdown') ?? []) await shutdown({type:'session_shutdown'}, ctx);
        for (const start of handlers.get('session_start') ?? []) await start({type:'session_start'}, ctx);
        const status: any = await ready;
        assert(!status.timeout, 'retained adapter initialization timed out');
        assert.deepEqual(status.servers.map(s => s.name).sort(), trusted
          ? ['both', 'projectOnly', 'remote', 'userOnly'] : ['both', 'remote', 'userOnly']);
        assertStopped(prior);
        assert.equal(pi.getActiveTools().includes('projectOnly_inspect'), trusted, 'stale direct tool surface');
        const mcp = tools.get('mcp');
        const result = await mcp.execute('switch-inspect', {tool:'both_inspect', args:{}}, undefined, undefined, ctx);
        assert(!result.details?.error, JSON.stringify(result));
        const text = JSON.stringify(result);
        assert(text.includes(cwd), 'stdio used stale cwd');
        assert(text.includes(trusted ? 'projectOverride' : 'both'), 'wrong tier selected');
        const forbidden = await mcp.execute('switch-denied', {tool:'projectOnly_inspect', args:{}}, undefined, undefined, ctx);
        assert.equal(!!forbidden.details?.error, !trusted, 'project tool authorization retained');
        for (const started of events().slice(prior.length)) {
          assert.equal(started.cwd, cwd, 'background server used stale cwd');
          if (!trusted) assert(!['projectOnly', 'projectOverride'].includes(started.name), 'denied project server started');
        }
        reports.push({cwd, trusted});
      } finally {clearTimeout(timer); off();}
    }
    for (const shutdown of handlers.get('session_shutdown') ?? []) await shutdown({type:'session_shutdown'}, original);
    assertStopped(events());
    writeFileSync(process.env.MCP_FIXTURE_REPORT!, JSON.stringify({ok:true, reports}));
  });
}
