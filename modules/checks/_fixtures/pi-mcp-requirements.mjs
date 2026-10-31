import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {parseRequiredMcpServers, readRequiredMcpServers, missingMcpServers, createRequiredMcpWarning} from '@adapter@/requirements.ts';

const sentence = 'MCP servers required for this role: `one`, `two`.';
assert.deepEqual(parseRequiredMcpServers(sentence), ['one', 'two']);
assert.deepEqual(parseRequiredMcpServers('no requirements here'), []);
assert.deepEqual(parseRequiredMcpServers('\t MCP  servers required\tfor this role :  `one` ,\t`two` .  \r\n'), ['one', 'two']);
assert.deepEqual(parseRequiredMcpServers('MCP servers required for this role: not a list.'), []);
assert.deepEqual(parseRequiredMcpServers(sentence.replace('`two`', '`one`')), ['one']);
// Actual registry renderer, not a second handwritten copy of its wording.
assert.deepEqual(parseRequiredMcpServers(readFileSync('@persona@', 'utf8')), ['one', 'two']);
assert.deepEqual(readRequiredMcpServers('@persona@'), ['one', 'two']);
assert.deepEqual(readRequiredMcpServers('/nonexistent/persona.md'), []);
writeFileSync('persona.md', sentence);
process.env.COTAL_AGENT_FILE = `${process.cwd()}/persona.md`;
assert.deepEqual(readRequiredMcpServers(), ['one', 'two']);
writeFileSync('persona.md', 'A plain persona without MCP requirements.');
assert.deepEqual(readRequiredMcpServers(), []);
delete process.env.COTAL_AGENT_FILE;
assert.deepEqual(readRequiredMcpServers(), []);

// Same snapshot as an initialized adapter with cached metadata: lazy servers
// have config entries but no connection and no recorded failure. They are usable.
const available = {configured: ['one', 'two'], disabled: [], failed: [], needsAuth: []};
const unavailable = {configured: ['one', 'disabled', 'failed', 'auth'], disabled: ['disabled'], failed: ['failed'], needsAuth: ['auth']};
assert.deepEqual(missingMcpServers(['one', 'two'], available), []);
assert.deepEqual(missingMcpServers(['one', 'absent', 'disabled', 'failed', 'auth', 'failed'], unavailable), [
  'not configured: absent', 'disabled: disabled', 'failed: failed', 'needs auth: auth',
]);
const notices = [], logs = [];
const ctx = {hasUI: true, ui: {notify: (...args) => notices.push(args)}};
const log = message => logs.push(message);
const lazy = createRequiredMcpWarning(['one', 'two']);
lazy(ctx, available, log);
lazy(ctx, unavailable, log); // Checked once, even if the first check was silent.
assert.equal(notices.length, 0);
assert.equal(logs.length, 0);
for (const [name, reason] of [['absent', 'not configured'], ['disabled', 'disabled'], ['failed', 'failed'], ['auth', 'needs auth']]) {
  const once = createRequiredMcpWarning([name]);
  once(ctx, unavailable, log);
  once(ctx, unavailable, log);
  assert.match(notices.at(-1)[0], new RegExp(`${reason}: ${name}`));
  assert.match(notices.at(-1)[0], /Warning only; this session will continue/);
  assert.equal(notices.at(-1)[1], 'warning');
}
assert.equal(notices.length, 4);
assert.equal(logs.length, 0);
const headless = {...ctx, hasUI: false};
const nextSession = createRequiredMcpWarning(['absent']);
nextSession(headless, unavailable, log);
nextSession(headless, unavailable, log);
assert.equal(logs.length, 1);
assert.equal(notices.length, 4);
for (const path of [undefined, '/nonexistent/persona.md', `${process.cwd()}/persona.md`]) {
  if (path === undefined) delete process.env.COTAL_AGENT_FILE;
  else process.env.COTAL_AGENT_FILE = path;
  createRequiredMcpWarning(readRequiredMcpServers())(ctx, unavailable, () => assert.fail('plain Pi must be silent'));
}
assert.equal(notices.length, 4);
assert.doesNotThrow(() => createRequiredMcpWarning(['absent'])({hasUI: true, ui: {notify() {throw Error('UI failed');}}}, unavailable, log));
assert.doesNotThrow(() => createRequiredMcpWarning(['absent'])(headless, unavailable, () => {throw Error('log failed');}));
assert.doesNotThrow(() => createRequiredMcpWarning(['absent'])(ctx, null, log));
console.log('MCP requirements: parser/renderCotal, lazy availability, missing/disabled/failed/auth reasons, warning once/UI/headless/silence/failure isolation passed');
