import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

pi = str(Path(sys.argv[1]).resolve())
adapter = '@adapter@'
probe = '''
import {writeFileSync} from 'node:fs';
export default function(pi) {
  let resolve;
  const snapshot = new Promise(r => {resolve = r;});
  pi.events.on('pi-mcp-adapter/status/v1', value => {if (value.servers.length) resolve(value);});
  pi.on('session_start', async () => {
    const timer = setTimeout(() => resolve({timeout: true}), 12000);
    const result = await snapshot;
    clearTimeout(timer);
    writeFileSync(process.env.MCP_FIXTURE_REPORT, JSON.stringify(result));
  });
}
'''

with tempfile.TemporaryDirectory(prefix='agentic-pi-mcp-') as tmp:
    base = Path(tmp)
    def run(name, *, integration=False, native=False, decision=None, ancestor=False, flags=()):
        root = base / name
        home = root / 'home'
        cwd = root / 'project'
        agent = home / '.pi/agent'
        shared = home / '.config/mcp'
        for directory in [cwd, agent, shared]:
            directory.mkdir(parents=True, exist_ok=True)
        user = json.loads(Path('@user@').read_text())
        project = json.loads(Path('@project@').read_text())
        if native:
            (cwd / '.pi/prompts').mkdir(parents=True)
        if decision is not None:
            trust_path = cwd.parent if ancestor else cwd
            (agent / 'trust.json').write_text(json.dumps({str(trust_path.resolve()): decision}))
        if not integration:
            # Avoid HTTP in trust-only scenarios; all launched processes are
            # fixture executables that record names/cwd, never credentials.
            (agent / 'mcp.json').write_text(json.dumps({'mcpServers': {'remote': {'disabled': True}}}))
            project['mcpServers']['both'].update(args=['projectOverride'], lifecycle='eager')
            project['mcpServers']['projectOnly']['lifecycle'] = 'eager'
        (shared / 'mcp.json').write_text(json.dumps(user))
        (cwd / '.mcp.json').write_text(json.dumps(project))
        report = root / 'report.json'
        events = root / 'events.jsonl'
        env = {
            'HOME': str(home), 'PATH': os.environ['PATH'],
            'PI_CODING_AGENT_DIR': str(agent), 'PI_OFFLINE': '1',
            'PI_TELEMETRY': '0', 'XDG_CACHE_HOME': str(root / 'cache'),
            'MCP_UI_VIEWER': 'none', 'MCP_FIXTURE_EVENTS': str(events),
            'MCP_FIXTURE_REPORT': str(report), 'MCP_FIXTURE_TOKEN': 'fake-runtime-token',
            'MCP_FIXTURE_KEY': 'fake-runtime-key', 'MCP_FIXTURE_URL': 'http://127.0.0.1:1/mcp',
            'MCP_FIXTURE_TRUSTED': 'yes' if integration else 'no',
        }
        cmd = [pi, '--offline', '--no-session', '--no-extensions', '--no-skills', '--no-context-files', '--mode', 'rpc', *flags]
        if integration:
            cmd += ['-e', '@extension@']
        else:
            probe_path = root / 'probe.ts'
            probe_path.write_text(probe)
            cmd += ['-e', adapter, '-e', str(probe_path)]
        result = subprocess.run(cmd, input='{"type":"get_commands","id":"check"}\n', text=True, capture_output=True, env=env, cwd=cwd, timeout=45)
        assert result.returncode == 0, (name, result.stderr)
        assert report.exists(), (name, result.stderr, result.stdout)
        data = json.loads(report.read_text())
        assert not data.get('timeout'), (name, result.stderr, result.stdout)
        for token in ['fake-runtime-token', 'fake-runtime-key']:
            assert token not in result.stdout + result.stderr, (name, 'credential leaked to output')
        # Check all adapter artifacts, including metadata and trace output.
        # Fixture code/configs contain variable references, never resolved bytes.
        for directory in [agent, cwd]:
            for file in directory.rglob('*'):
                if file.is_file():
                    contents = file.read_bytes()
                    assert b'fake-runtime-token' not in contents, (name, str(file))
                    assert b'fake-runtime-key' not in contents, (name, str(file))
        spawned = [json.loads(line)['name'] for line in events.read_text().splitlines()] if events.exists() else []
        return data, spawned

    data, _ = run('transports', integration=True, flags=['--approve'])
    assert data.get('ok'), data
    print('PASS: real Pi loader; stdio wrappers/cwd; HTTP interpolation; proxy search/describe/call; cold/warm/eager lifecycle; credential-free artifacts')
    for name, native, decision, ancestor, flags, trusted in [
        ('bare-default', False, None, False, [], False),
        ('bare-saved-deny', False, False, False, [], False),
        ('bare-saved-trust', False, True, False, [], True),
        ('bare-parent-trust', False, True, True, [], True),
        ('bare-approve', False, None, False, ['--approve'], True),
        ('bare-cli-deny', False, True, False, ['--no-approve'], False),
        ('native-default', True, None, False, [], False),
        ('native-deny', True, False, False, [], False),
        ('native-trust', True, True, False, [], True),
    ]:
        data, spawned = run(name, native=native, decision=decision, ancestor=ancestor, flags=flags)
        names = sorted(server['name'] for server in data['servers'])
        expected = ['both', 'projectOnly', 'remote', 'userOnly'] if trusted else ['both', 'remote', 'userOnly']
        assert names == expected, (name, names, data)
        assert ('projectOnly' in spawned) == trusted, (name, spawned)
        assert ('projectOverride' in spawned) == trusted, (name, spawned)
        assert 'userOnly' in spawned, (name, spawned)
        print('PASS:', name, 'project admitted' if trusted else 'user tier only')
