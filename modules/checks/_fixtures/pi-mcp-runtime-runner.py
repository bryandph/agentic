import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

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
    def run(name, *, integration=False, retained=False, switches=False, native=False, decision=None, ancestor=False, flags=()):
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
        if retained or switches:
            project['mcpServers']['projectOnly']['directTools'] = True
        (shared / 'mcp.json').write_text(json.dumps(user))
        (cwd / '.mcp.json').write_text(json.dumps(project))
        sequence = []
        if retained or switches:
            other = root / 'other-project'
            other.mkdir()
            (other / '.mcp.json').write_text(json.dumps(project))
            decisions = {str(cwd.resolve()): decision is not False, str(other.resolve()): decision is False}
            (agent / 'trust.json').write_text(json.dumps(decisions))
            sequence = [{'cwd': str(path.resolve()), 'trusted': decisions[str(path.resolve())]}
                        for path in [cwd, other, cwd, other, cwd]]
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
            'MCP_FIXTURE_SEQUENCE': json.dumps(sequence),
        }
        cmd = [pi, '--offline', '--no-session', '--no-extensions', '--no-skills', '--no-context-files', '--mode', 'rpc', *flags]
        if retained:
            cmd += ['-e', '@sessionExtension@']
        elif integration:
            cmd += ['-e', '@extension@']
        else:
            probe_path = root / 'probe.ts'
            probe_path.write_text(probe if not switches else probe.replace(
                "writeFileSync(process.env.MCP_FIXTURE_REPORT, JSON.stringify(result));",
                "writeFileSync(process.env.MCP_FIXTURE_REPORT, JSON.stringify({...result, cwd: ctx.cwd}));"
            ).replace("async () => {", "async (event, ctx) => {"))
            cmd += ['-e', adapter, '-e', str(probe_path)]
        if switches:
            stdout = root / 'stdout'
            stderr = root / 'stderr'
            with stdout.open('w') as out, stderr.open('w') as err:
                proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=out, stderr=err, text=True, env=env, cwd=cwd)
                try:
                    def wait_report(expected):
                        deadline = time.monotonic() + 20
                        while not report.exists() and proc.poll() is None and time.monotonic() < deadline:
                            time.sleep(0.02)
                        assert report.exists(), (name, stdout.read_text(), stderr.read_text())
                        snapshot = json.loads(report.read_text())
                        assert snapshot['cwd'] == expected['cwd'], (name, 'actual Pi cwd', snapshot['cwd'], expected)
                        names = sorted(server['name'] for server in snapshot['servers'])
                        assert names == (['both', 'projectOnly', 'remote', 'userOnly'] if expected['trusted'] else ['both', 'remote', 'userOnly']), (name, snapshot)
                    def wait_response(request_id):
                        deadline = time.monotonic() + 20
                        while time.monotonic() < deadline and proc.poll() is None:
                            for line in stdout.read_text().splitlines():
                                try:
                                    response = json.loads(line)
                                except json.JSONDecodeError:
                                    continue  # final line may still be in flight
                                if response.get('id') == request_id and response.get('type') == 'response':
                                    assert response['success'] and not response.get('data', {}).get('cancelled'), response
                                    return
                            time.sleep(0.02)
                        raise AssertionError((name, 'missing RPC acknowledgement', request_id, stdout.read_text(), stderr.read_text()))
                    wait_report(sequence[0])
                    for index, step in enumerate(sequence[1:]):
                        session = root / f'session-{index}.jsonl'
                        session.write_text(json.dumps({'type':'session', 'version':3, 'id':str(uuid.uuid4()), 'timestamp':'2026-09-10T00:00:00.000Z', 'cwd':step['cwd']}) + '\n')
                        report.unlink()
                        proc.stdin.write(json.dumps({'type':'switch_session', 'sessionPath':str(session), 'id':f'switch-{index}'}) + '\n')
                        proc.stdin.flush()
                        wait_response(f'switch-{index}')
                        wait_report(step)
                        report.unlink()
                        proc.stdin.write(json.dumps({'type':'new_session', 'id':f'new-{index}'}) + '\n')
                        proc.stdin.flush()
                        wait_response(f'new-{index}')
                        wait_report(step)
                    proc.stdin.close()
                    proc.wait(timeout=15)
                finally:
                    if proc.poll() is None:
                        proc.kill()
                        proc.wait()
            result = subprocess.CompletedProcess(cmd, proc.returncode, stdout.read_text(), stderr.read_text())
        else:
            result = subprocess.run(cmd, input='{"type":"get_commands","id":"check"}\n', text=True, capture_output=True, env=env, cwd=cwd, timeout=45)
        assert result.returncode == 0, (name, result.stderr)
        assert report.exists(), (name, result.stderr, result.stdout)
        data = json.loads(report.read_text())
        assert not data.get('timeout'), (name, result.stderr, result.stdout)
        for token in ['fake-runtime-token', 'fake-runtime-key']:
            assert token not in result.stdout + result.stderr, (name, 'credential leaked to output')
        # Check all adapter artifacts, including metadata and trace output.
        # Fixture code/configs contain variable references, never resolved bytes.
        for directory in [agent, cwd] + ([other] if retained or switches else []):
            for file in directory.rglob('*'):
                if file.is_file():
                    contents = file.read_bytes()
                    assert b'fake-runtime-token' not in contents, (name, str(file))
                    assert b'fake-runtime-key' not in contents, (name, str(file))
        records = [json.loads(line) for line in events.read_text().splitlines()] if events.exists() else []
        if retained or switches:
            for record in records:
                if not decisions[record['cwd']]:
                    assert record['name'] not in ['projectOnly', 'projectOverride'], (name, 'denied project process started', record)
        spawned = [record['name'] for record in records]
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

    data, spawned = run('retained-session-switch', retained=True)
    assert data.get('ok') and len(data['reports']) == 5, data
    print('PASS: retained real adapter instance; trusted A -> denied B -> A -> B -> A; shutdown/start and repeated start; actual proxy calls and cwd')

    data, _ = run('retained-denied-first', retained=True, decision=False)
    assert data.get('ok'), data
    print('PASS: retained instance initially denied -> trusted -> denied; no cached global-only selection')
    run('rpc-session-switch', switches=True)
    run('rpc-denied-first', switches=True, decision=False)
    print('PASS: one Pi process; actual RPC switch_session and new_session across both trust directions')
