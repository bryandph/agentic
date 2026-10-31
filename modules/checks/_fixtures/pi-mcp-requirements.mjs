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
assert.deepEqual(missingMcpServers(['one', 'two', 'failed', 'two'], ['one', 'extra']), ['two', 'failed']);

const notices = [], logs = [];
const ctx = {hasUI: true, ui: {notify: (...args) => notices.push(args)}};
const warn = createRequiredMcpWarning(['one', 'failed', 'absent']);
warn(ctx, ['one'], message => logs.push(message));
warn(ctx, [], message => logs.push(message));
assert.equal(notices.length, 1);
assert.equal(notices[0][1], 'warning');
assert.match(notices[0][0], /failed, absent/);
assert.match(notices[0][0], /Warning only; this session will continue/);
assert.equal(logs.length, 0);
const headless = {...ctx, hasUI: false};
const nextSession = createRequiredMcpWarning(['one']);
nextSession(headless, [], message => logs.push(message));
nextSession(headless, [], message => logs.push(message));
assert.equal(logs.length, 1);
assert.equal(notices.length, 1);
createRequiredMcpWarning(['one'])(ctx, ['one'], () => assert.fail('unexpected warning'));
createRequiredMcpWarning([])(ctx, [], () => assert.fail('unexpected warning'));
assert.equal(notices.length, 1);
for (const path of [undefined, '/nonexistent/persona.md', `${process.cwd()}/persona.md`]) {
  if (path === undefined) delete process.env.COTAL_AGENT_FILE;
  else process.env.COTAL_AGENT_FILE = path;
  createRequiredMcpWarning(readRequiredMcpServers())(ctx, [], () => assert.fail('plain Pi must be silent'));
}
assert.equal(notices.length, 1);
assert.doesNotThrow(() => createRequiredMcpWarning(['one'])({hasUI: true, ui: {notify() {throw Error('UI failed');}}}, [], () => {}));
assert.doesNotThrow(() => createRequiredMcpWarning(['one'])(headless, [], () => {throw Error('log failed');}));
assert.doesNotThrow(() => createRequiredMcpWarning(['one'])(ctx, null, () => {}));
console.log('MCP requirements: parser, renderCotal agreement, missing set, warning once/UI/headless/failure isolation passed');
