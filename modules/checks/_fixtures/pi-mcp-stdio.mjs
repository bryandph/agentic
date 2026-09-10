// Minimal legacy MCP server; only fake credentials are used by the harness.
import {createInterface} from 'node:readline';
import {appendFileSync} from 'node:fs';
const name = process.argv[2];
appendFileSync(process.env.MCP_FIXTURE_EVENTS, JSON.stringify({name, cwd: process.cwd(), pid: process.pid, event: 'start'}) + '\n');
for await (const line of createInterface({input: process.stdin})) {
  const request = JSON.parse(line);
  if (request.id === undefined) continue;
  let result;
  if (request.method === 'initialize') {
    result = {protocolVersion: '2025-11-25', capabilities: {tools: {}}, serverInfo: {name: 'fixture', version: '1'}};
  } else if (request.method === 'tools/list') {
    result = {tools: [{name: 'inspect', description: 'Inspect fixture cwd and secret presence without returning the secret', inputSchema: {type: 'object', properties: {}}}]};
  } else if (request.method === 'tools/call') {
    result = {content: [{type: 'text', text: JSON.stringify({name, cwd: process.cwd(), tokenPresent: process.env.MCP_FIXTURE_TOKEN === 'fake-runtime-token'})}]};
  } else result = {};
  process.stdout.write(JSON.stringify({jsonrpc: '2.0', id: request.id, result}) + '\n');
}
