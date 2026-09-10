import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {createRequire} from 'node:module';
import {loadMcpConfig, loadGlobalMcpConfig, writeProjectServerDisabledOverride} from '@adapter@/config.ts';
import {resolveCommandSecretsRecord} from '@adapter@/utils.ts';
import {computeServerHash} from '@adapter@/metadata-cache.ts';

const userPath = join(process.env.HOME, '.config/mcp/mcp.json');
const projectPath = join(process.cwd(), '.mcp.json');
const rawUser = readFileSync(userPath, 'utf8');
const rawProject = readFileSync(projectPath, 'utf8');
const user = JSON.parse(rawUser).mcpServers;
const project = JSON.parse(rawProject).mcpServers;
const names = value => Object.keys(value).sort();
assert.deepEqual(names(user), ['both', 'remote', 'userOnly']);
assert.deepEqual(names(project), ['both', 'projectOnly', 'remote']);
const merged = loadMcpConfig().mcpServers;
assert.deepEqual(names(merged), [...new Set([...names(user), ...names(project)])].sort());
assert.deepEqual(loadGlobalMcpConfig().mcpServers, user);
assert.equal(merged.both.command, user.both.command);
assert.equal(merged.both.command, project.both.command);
assert.match(merged.both.command, /^\/nix\/store\//);
assert.match(readFileSync(merged.both.command, 'utf8'), /printenv MCP_FIXTURE_TOKEN/);
assert.equal(merged.remote.headers.Authorization, 'Bearer ${MCP_FIXTURE_TOKEN}');
process.env.MCP_FIXTURE_URL = 'http://127.0.0.1:1/mcp';
const hash = computeServerHash(merged.remote);
process.env.MCP_FIXTURE_TOKEN = 'fake-runtime-token';
process.env.MCP_FIXTURE_KEY = 'fake-runtime-key';
assert.deepEqual(resolveCommandSecretsRecord(merged.remote.headers, key => key), {
  Authorization: 'Bearer fake-runtime-token', 'X-Api-Key': 'fake-runtime-key',
});
// Upstream invalidates metadata on credential rotation using a SHA-256 digest;
// only the digest, not the resolved configuration, is persisted in the cache.
assert.notEqual(computeServerHash(merged.remote), hash);
assert.equal(merged.remote.headers.Authorization, 'Bearer ${MCP_FIXTURE_TOKEN}');
// Overrides merge fields, project tier wins, and redirected endpoints cannot
// inherit a lower tier's credentials. Shared source files are never rewritten.
mkdirSync('.pi', {recursive: true});
writeFileSync('.pi/mcp.json', JSON.stringify({mcpServers: {
  both: {args: ['override'], lifecycle: 'eager'},
  remote: {url: 'https://other.fixture.example/mcp'},
}}));
const overridden = loadMcpConfig().mcpServers;
assert.equal(overridden.both.command, merged.both.command);
assert.deepEqual(overridden.both.args, ['override']);
assert.equal(overridden.remote.headers, undefined);
writeProjectServerDisabledOverride(undefined, process.cwd(), 'both', true);
assert.equal(loadMcpConfig().mcpServers.both.disabled, true);
writeProjectServerDisabledOverride(undefined, process.cwd(), 'both', false);
assert.notEqual(loadMcpConfig().mcpServers.both.disabled, true);
assert.equal(readFileSync(userPath, 'utf8'), rawUser);
assert.equal(readFileSync(projectPath, 'utf8'), rawProject);
for (const file of [userPath, projectPath, '.pi/mcp.json']) {
  assert.doesNotMatch(readFileSync(file, 'utf8'), /fake-runtime-(token|key)/);
}
// Load the packaged native module without opening or reading any credential store.
const require = createRequire('@adapter@/package.json');
assert.equal(typeof require('@napi-rs/keyring').Entry, 'function');
console.log('Pi shared user/project parity, immutable interpolation, overrides, and native dependency load passed');
