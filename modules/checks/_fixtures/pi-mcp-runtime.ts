import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFileSync, writeFileSync, existsSync, mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {initializeMcp} from '@adapter@/init.ts';
import {createMcpRuntimeOwner} from '@adapter@/runtime-owner.ts';
import {loadMcpConfig, loadGlobalMcpConfig} from '@adapter@/config.ts';
import {executeCall, executeDescribe, executeSearch} from '@adapter@/proxy-modes.ts';
import {projectConfigTrusted} from '@adapter@/agentic.ts';

export default function testExtension(pi) {
  pi.on('session_start', async (_event, ctx) => {
    const report = process.env.MCP_FIXTURE_REPORT!;
    const states: any[] = [];
    const owners: any[] = [];
    let requests = 0;
    const http = createServer(async (req, res) => {
      try {
        assert.equal(req.headers.authorization, 'Bearer fake-runtime-token');
        assert.equal(req.headers['x-api-key'], 'fake-runtime-key');
        requests++;
        if (req.method !== 'POST') {res.writeHead(405).end(); return;}
        const chunks: Buffer[] = [];
        for await (const chunk of req) chunks.push(chunk);
        const message = JSON.parse(Buffer.concat(chunks).toString());
        if (message.id === undefined) {res.writeHead(202).end(); return;}
        const result = message.method === 'initialize'
          ? {protocolVersion: '2025-11-25', capabilities: {tools: {}}, serverInfo: {name: 'fixture-http', version: '1'}}
          : message.method === 'tools/list'
          ? {tools: [{name: 'inspect', description: 'Fixture HTTP inspection', inputSchema: {type: 'object', properties: {}}}]}
          : {content: [{type: 'text', text: 'http-ok'}]};
        res.writeHead(200, {'content-type': 'application/json'}).end(JSON.stringify({jsonrpc: '2.0', id: message.id, result}));
      } catch {
        res.writeHead(500).end('fixture request validation failed');
      }
    });
    const stop = async state => {
      await state.owner.stop('fixture cleanup');
      await state.lifecycle.gracefulShutdown();
    };
    try {
      await new Promise<void>(resolve => http.listen(0, '127.0.0.1', resolve));
      process.env.MCP_FIXTURE_URL = `http://127.0.0.1:${(http.address() as any).port}/mcp`;
      process.env.MCP_FIXTURE_TOKEN = 'fake-runtime-token';
      process.env.MCP_FIXTURE_KEY = 'fake-runtime-key';
      const config = loadMcpConfig(undefined, ctx.cwd);
      config.settings = {sampling: false, elicitation: false, trace: {enabled: true}};
      for (const server of Object.values(config.mcpServers) as any[]) server.oauth = false;
      const fakePi = {events: pi.events, getFlag: () => undefined, sendMessage: () => {}, getAllTools: () => []};
      const quietCtx = {...ctx, cwd: ctx.cwd, mode: 'print', hasUI: false, modelRegistry: undefined};
      const start = async () => {
        const owner = createMcpRuntimeOwner();
        owners.push(owner);
        const state = await initializeMcp(fakePi as any, quietCtx as any, owner, {config});
        states.push(state);
        return state;
      };
      const starts = () => existsSync(process.env.MCP_FIXTURE_EVENTS!)
        ? readFileSync(process.env.MCP_FIXTURE_EVENTS!, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line))
        : [];
      // Exact parity at the live adapter state, plus actual cold-cache behavior.
      const cold = await start();
      assert.deepEqual(Object.keys(cold.config.mcpServers).sort(), ['both', 'projectOnly', 'remote', 'userOnly']);
      for (const name of Object.keys(config.mcpServers)) assert.equal(cold.manager.getConnection(name)?.status, 'connected', name);
      assert.equal(starts().length, 3);
      assert.ok(starts().every(entry => entry.cwd === ctx.cwd));
      assert.ok(requests > 0);
      await stop(cold);
      const beforeWarm = starts().length;
      const warm = await start();
      assert.equal(starts().length, beforeWarm, 'cached lazy servers must not spawn');
      for (const name of Object.keys(config.mcpServers)) assert.equal(warm.manager.getConnection(name), undefined);
      const search = await executeSearch(warm, 'inspect');
      assert.ok(JSON.stringify(search).includes('both_inspect'));
      const describe = await executeDescribe(warm, 'both_inspect');
      assert.ok(JSON.stringify(describe).includes('inspect'));
      assert.equal(starts().length, beforeWarm, 'search/describe stay offline');
      const call = await executeCall(warm, 'both_inspect', {}, undefined);
      const text = JSON.stringify(call);
      assert.ok(text.includes('tokenPresent'));
      assert.ok(text.includes('true'));
      assert.ok(text.includes(ctx.cwd));
      assert.equal(starts().length, beforeWarm + 1);
      await executeCall(warm, 'remote_inspect', {}, undefined);
      await stop(warm);
      config.mcpServers.userOnly.lifecycle = 'eager';
      const eager = await start();
      assert.equal(eager.manager.getConnection('userOnly')?.status, 'connected');
      assert.equal(eager.manager.getConnection('both'), undefined);
      await stop(eager);
      // Invalid interpolated header values fail without reproducing token bytes.
      process.env.MCP_FIXTURE_TOKEN = 'fake-runtime-token\ninvalid';
      const invalid = await start();
      await assert.rejects(invalid.manager.connect('remote', config.mcpServers.remote), error => {
        assert.ok(!String(error).includes('fake-runtime-token'));
        return true;
      });
      await stop(invalid);
      // Trust uses the real Pi context in all runner scenarios. In an ordinary
      // bare-MCP cwd, implicit true is not an approval of project commands.
      assert.equal(projectConfigTrusted(ctx), process.env.MCP_FIXTURE_TRUSTED === 'yes');
      const global = loadGlobalMcpConfig();
      assert.deepEqual(Object.keys(global.mcpServers).sort(), ['both', 'remote', 'userOnly']);
      assert.equal(global.mcpServers.projectOnly, undefined);
      for (const path of [join(ctx.cwd, '.mcp.json'), join(process.env.HOME!, '.config/mcp/mcp.json'), join(process.env.PI_CODING_AGENT_DIR!, 'mcp-cache.json')]) {
        assert.ok(!readFileSync(path, 'utf8').includes('fake-runtime-token'));
      }
      writeFileSync(report, JSON.stringify({ok: true, requests, starts: starts().length}));
    } catch (error) {
      writeFileSync(report, JSON.stringify({ok: false, error: String(error), stack: (error as Error).stack}));
    } finally {
      for (const owner of owners) await owner.stop('fixture finished');
      for (const state of states) await state.lifecycle.gracefulShutdown();
      http.closeAllConnections();
      await new Promise<void>(resolve => http.close(() => resolve()));
    }
  });
}
