"""Sandbox qualification: fake executables, fixtures, and an injected clock."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path(__file__).parent
spec = importlib.util.spec_from_file_location('attention_watch', ROOT / 'attention_watch.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)
SENTINEL = 'NEVER_EXPORT_PENDING_OR_CREDENTIAL_9182'

FAKE = r'''#!PYTHON
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
f = json.loads(pathlib.Path(os.environ['WATCH_FIXTURE']).read_text())
if (name == 'cotal' and args[0] == 'send') or (name == 'herdr' and args[:2] == ['notification','show']):
    with open(os.environ['WATCH_DELIVERIES'], 'a') as h:
        h.write(json.dumps([name, args]) + '\n')
    sys.exit(f.get('deliveryExit', 0))
key = name
if name == 'cotal': key += ':' + args[0]
if name == 'herdr': key += ':' + ':'.join(args[:2])
if key in f.get('fail', []):
    print('NEVER_EXPORT_PENDING_OR_CREDENTIAL_9182', file=sys.stderr)
    sys.exit(1)
v = f[key]
print(v if isinstance(v, str) else json.dumps({'result': v}))
'''


class Sandbox(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.now = 2_000_000_000
        self.c = a.config()
        for key in ('state_dir', 'snapshot_dir', 'ci_dir', 'workspace_root'):
            self.c[key] = str(self.root / key)
            Path(self.c[key]).mkdir()
        self.c['admin_creds'] = str(self.root / 'admin.creds')
        self.fixture_path = self.root / 'fixture.json'
        self.delivery_path = self.root / 'deliveries.jsonl'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ('cotal', 'herdr', 'ps', 'lsof'):
            path = self.bin / name
            path.write_text(FAKE.replace('PYTHON', sys.executable))
            path.chmod(0o755)
        self.old_env = os.environ.copy()
        os.environ.update(PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                          WATCH_FIXTURE=str(self.fixture_path), WATCH_DELIVERIES=str(self.delivery_path))
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(self.old_env)))
        self.fixture = {
            'cotal:endpoints': {'kind': 'live-presence', 'items': [self.peer('operator', 'seat'), self.peer('worker')]},
            'cotal:pending': {'pending': 1, 'ackPending': 0, 'ackFloor': 1, 'delivered': 2,
                              'durable': SENTINEL, 'candidates': [{'id': SENTINEL, 'from': SENTINEL, 'ts': (self.now - 10000)*1000}]},
            'herdr:agent:list': {'agents': []},
            'herdr:pane:process-info': {'process_info': {'foreground_processes': [{'pid': os.getpid(), 'argv': [SENTINEL]}]}},
            'ps': '', 'lsof': 'p123\nn' + self.c['workspace_root'] + '\n',
        }
        self.snapshot('worker')
        self.write_fixture()
        self.w = a.Watcher(self.c, clock=lambda: self.now)

    def peer(self, name, role='worker', ages='', condition='', status='working'):
        return {'name': name, 'role': role, 'kind': 'agent', 'reportedStatus': status,
                'facts': {'condition': condition, 'ages': ages}, 'activityAge': ''}

    def write_fixture(self):
        self.fixture_path.write_text(json.dumps(self.fixture))

    def credential(self, mode=0o600):
        path = Path(self.c['admin_creds'])
        path.write_text(SENTINEL)
        path.chmod(mode)

    def snapshot(self, name, **extra):
        data = {'schema': 'agentic.seat-snapshot/1', 'space': self.c['space'], 'name': name,
                'pid': os.getpid(), 'cwd': self.c['workspace_root'], 'writtenAt': self.now*1000,
                'connection': {'automaticCount': 0, 'automaticQueueStalledForMs': 0}}
        data.update(extra)
        (Path(self.c['snapshot_dir']) / (name + '.json')).write_text(json.dumps(data))

    def observe(self):
        self.write_fixture()
        self.w.observe()
        return {v['kind'] for v in self.w.findings}

    def restart(self):
        state_path = self.root / 'state.json'
        a.save(state_path, self.w.state)
        self.w = a.Watcher(self.c, a.read_json(state_path), clock=lambda: self.now)

    def emit(self):
        deliveries = self.w.deliver()
        # Execute exactly the delivery command shapes the CLI uses.
        for d in deliveries:
            args = ['cotal', 'send', '--space', self.c['space'], '-t', d['target'], d['text']] if d['route'] == 'dm' else ['herdr', 'notification', 'show', 'Agentic attention', '--body', d['text'], '--sound', 'none']
            a.command(args, structured=False)
        return deliveries

    def finding(self, subject='worker', kind='rate_limit'):
        self.w.findings = []
        self.w.seats = ['operator']
        self.w.add(kind, subject, 'age=1000s', 600)

    def test_s1_text_threshold_crossings(self):
        for kind, limit in [('rate_limit', 600), ('approval', 900), ('input', 900)]:
            with self.subTest(kind=kind):
                p = self.fixture['cotal:endpoints']['items'][1]
                p['facts']['condition'] = f'{kind} for {limit-1}s'
                self.assertNotIn(kind, self.observe())
                p['facts']['condition'] = f'{kind} for {limit}s'
                self.assertIn(kind, self.observe())
        p['facts']['ages'] = ' · unchanged for 40m · active 3h ago'
        self.assertIn('working-stale', self.observe())
        p['facts']['ages'] = ' · unchanged for 40m'
        self.assertNotIn('working-stale', self.observe())
        # Offline entries and nonlocal workers cannot become work findings.
        p['reportedStatus'] = 'offline'
        self.assertNotIn('rate_limit', self.observe())

    def test_s2_floor_stall_restart_advance_zero_and_privacy(self):
        self.credential()
        self.assertNotIn('broker-backlog', self.observe())  # old candidate alone never fires
        self.now += 900
        self.restart()
        self.assertIn('broker-backlog', self.observe())
        self.fixture['cotal:pending']['ackFloor'] = 2
        self.assertNotIn('broker-backlog', self.observe())
        self.now += 900
        self.assertIn('broker-backlog', self.observe())
        self.fixture['cotal:pending']['pending'] = 0
        self.assertNotIn('broker-backlog', self.observe())
        self.fixture['cotal:pending']['pending'] = 1
        self.assertNotIn('broker-backlog', self.observe())
        self.now += 900
        self.assertIn('broker-backlog', self.observe())
        self.w.deliver()
        self.now += 120
        deliveries = self.emit()
        self.assertTrue(deliveries)
        self.assertNotIn(SENTINEL, json.dumps(self.w.state) + json.dumps(self.w.report()) + self.delivery_path.read_text())

    def test_s3_queue_and_stale_snapshot(self):
        self.snapshot('worker', connection={'automaticCount': 2, 'automaticQueueStalledForMs': 899000})
        self.assertNotIn('queue-stalled', self.observe())
        self.snapshot('worker', connection={'automaticCount': 2, 'automaticQueueStalledForMs': 900000})
        self.assertIn('queue-stalled', self.observe())
        self.now += 181
        self.assertIn('snapshot-stale', self.observe())
        self.snapshot('worker', pid=999999999)
        self.assertIn('snapshot-stale', self.observe())
        self.snapshot('worker', schema='future')
        self.observe()
        self.assertEqual(self.w.sources['S3'], 'unavailable')

    def test_s4_blocked_restart_and_reset(self):
        self.fixture['herdr:agent:list']['agents'] = [{'pane_id': 'p1', 'agent_status': 'blocked', 'cwd': self.c['workspace_root']}]
        self.assertNotIn('herdr-blocked', self.observe())
        self.now += 599
        self.assertNotIn('herdr-blocked', self.observe())
        self.restart()
        self.now += 1
        self.assertIn('herdr-blocked', self.observe())
        self.fixture['herdr:agent:list']['agents'][0]['agent_status'] = 'working'
        self.assertNotIn('herdr-blocked', self.observe())
        self.fixture['herdr:agent:list']['agents'][0]['agent_status'] = 'blocked'
        self.assertNotIn('herdr-blocked', self.observe())

    def test_s5_git_age_and_cwd(self):
        self.fixture['ps'] = '123 19:59 /usr/bin/git\n124 01:00:00 /usr/bin/bash'
        self.assertNotIn('git-hung', self.observe())
        self.fixture['ps'] = '123 20:00 /usr/bin/git'
        self.assertIn('git-hung', self.observe())
        self.fixture['lsof'] = 'p123\nn/outside\n'
        self.assertNotIn('git-hung', self.observe())
        self.fixture['lsof'] = 'p123\nn' + self.c['workspace_root'] + '-not-child\n'
        self.assertNotIn('git-hung', self.observe())

    def ci_fixture(self, **extra):
        path = Path(self.c['ci_dir']) / 'sessions/s1/watches/w1'
        path.mkdir(parents=True, exist_ok=True)
        state = {'phase': 'pending', 'observedAt': self.now, 'pid': os.getpid()}
        state.update(extra)
        (path / 'state.json').write_text(json.dumps(state))
        (path / 'watch.json').write_text(json.dumps({'deadlineAt': self.now + 600, 'cadence': {'initialSeconds': 30, 'maxSeconds': 90}}))
        return path

    def test_s6_ci_stale_dead_expired_terminal(self):
        path = self.ci_fixture(observedAt=self.now - 270)
        self.assertNotIn('ci-watch-stale', self.observe())
        self.now += 1
        self.assertIn('ci-watch-stale', self.observe())
        self.ci_fixture(pid=999999999)
        self.assertIn('ci-watch-stale', self.observe())
        self.ci_fixture()
        (path / 'watch.json').write_text(json.dumps({'deadlineAt': self.now - 1, 'cadence': {'maxSeconds': 90}}))
        self.assertIn('ci-watch-stale', self.observe())
        self.ci_fixture(phase='running', lastObservation={'phase': 'pending'}, pid=999999999)
        self.assertIn('ci-watch-stale', self.observe())
        self.ci_fixture(phase='running', lastObservation={'phase': 'pending'}, pid=999999999)
        (path / 'watch.json').write_text(json.dumps({'deadlineAt': self.now + 600, 'cadence': {}}))
        self.assertIn('ci-watch-stale', self.observe())
        self.ci_fixture(phase='terminal', pid=999999999)
        self.assertNotIn('ci-watch-stale', self.observe())

    def test_coalesce_restart_dedupe_reminder_resolved(self):
        self.finding()
        self.assertEqual(self.emit(), [])
        self.now += 60
        self.w.add('approval', 'other', 'waiting 900s', 900)
        self.assertEqual(self.emit(), [])
        self.now += 60
        self.assertEqual(len(self.emit()), 1)
        self.restart()
        self.finding()
        self.assertEqual(self.emit(), [])
        self.now += 7199
        self.assertEqual(self.emit(), [])
        self.now += 1
        self.assertEqual(self.emit(), [])  # reminder also goes through coalescing
        self.now += 120
        self.assertEqual(len(self.emit()), 1)
        self.w.findings = []
        self.assertEqual(self.emit(), [])
        self.finding('new')
        self.emit()
        self.now += 120
        self.assertIn('resolved since last', self.emit()[0]['text'])
        self.assertNotIn(SENTINEL, self.delivery_path.read_text())

    def test_hourly_cap_and_recovery(self):
        for i in range(7):
            self.finding(str(i))
            self.emit()
            self.now += 120
            result = self.emit()
            self.assertEqual(len(result), 1 if i < 6 else 0)
            self.now += 1
        self.restart()
        self.finding('6')
        self.assertEqual(self.emit(), [])
        self.now += 3600
        self.assertEqual(len(self.emit()), 1)

    def test_human_routing_at_most_once_and_no_later_dm(self):
        for seats, subject in [(['operator'], 'operator'), ([], 'worker'), (['one', 'two'], 'worker')]:
            with self.subTest(seats=seats):
                self.w.state['events'] = {}
                self.finding(subject)
                self.w.seats = seats
                self.emit()
                self.now += 120
                d = self.emit()
                self.assertEqual(d[0]['route'], 'notification')
                self.restart()
                self.finding(subject)
                self.w.seats = ['new-seat']
                self.now += 10000
                self.assertEqual(self.emit(), [])

    def test_source_failure_routes_human_with_sanitized_errors(self):
        self.fixture['fail'] = ['cotal:endpoints', 'herdr:agent:list', 'ps']
        self.observe()
        self.w.deliver()
        self.now += 120
        d = self.emit()
        self.assertEqual({v['route'] for v in d}, {'notification'})
        self.assertNotIn(SENTINEL, json.dumps(self.w.report()) + self.delivery_path.read_text())

    def test_cli_credential_modes_absence_dryrun_status_privacy(self):
        config_path = self.root / 'config.json'
        config_path.write_text(json.dumps(self.c))
        def cli(*args):
            return subprocess.run([sys.executable, str(ROOT / 'attention_watch.py'), '--config', str(config_path), *args], capture_output=True, text=True)
        self.credential(0o644)
        result = cli('run', '--once', '--dry-run')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('mode 0600', result.stderr)
        self.assertFalse(self.delivery_path.exists())
        self.credential()
        result = cli('run', '--once', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(SENTINEL, result.stdout + result.stderr)
        Path(self.c['admin_creds']).unlink()
        result = cli('run', '--once', '--dry-run')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)['report']['sources']['S2'], 'unavailable')
        self.assertFalse(self.delivery_path.exists())
        self.assertFalse((Path(self.c['state_dir']) / 'state.json').exists())
        result = cli('status', '--json')
        self.assertIn('unavailable', result.stdout)
        self.assertNotIn(SENTINEL, result.stdout + result.stderr)

    def test_credential_ownership_and_symlink_refused(self):
        self.credential()
        with patch.object(a.os, 'getuid', return_value=os.getuid() + 1):
            with self.assertRaisesRegex(ValueError, 'owned by this user'):
                a.credential_available(self.c)
        other = self.root / 'other'
        other.write_text(SENTINEL)
        Path(self.c['admin_creds']).unlink()
        Path(self.c['admin_creds']).symlink_to(other)
        with self.assertRaises(ValueError):
            a.credential_available(self.c)

    def test_unreadable_source_is_unknown_not_resolved_or_resent(self):
        self.fixture['cotal:endpoints']['items'][1]['facts']['condition'] = 'rate_limit for 12m'
        self.observe()
        self.w.deliver()
        self.now += 120
        self.emit()
        self.fixture['fail'] = ['cotal:endpoints']
        self.observe()
        self.w.deliver()
        self.assertTrue(self.w.state['events']['rate_limit:worker']['active'])
        self.assertFalse(any('rate_limit:worker' in s for s in self.w.state['resolved']))
        self.now += 10000
        self.assertEqual({d['route'] for d in self.emit()}, {'notification'})

    def test_cli_persists_reservation_before_failed_delivery(self):
        config_path = self.root / 'config.json'
        config_path.write_text(json.dumps(self.c))
        self.fixture['deliveryExit'] = 1
        self.write_fixture()
        state = {'events': {}, 'sent': [], 'resolved': [], 'seen': {}}
        w = a.Watcher(self.c, state, clock=lambda: self.now - 3600)
        w.unavailable('S2')
        w.reconcile()
        # Reserve a pre-existing transition so --once will attempt a notification.
        state_path = Path(self.c['state_dir']) / 'state.json'
        a.save(state_path, state)
        # Use wall-clock-relative first observation, not our fixture epoch.
        state['events']['source-unavailable:S2']['first'] = 1
        a.save(state_path, state)
        args = [sys.executable, str(ROOT / 'attention_watch.py'), '--config', str(config_path), 'run', '--once']
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(a.read_json(state_path)['events']['source-unavailable:S2']['notified'])
        self.assertEqual(a.read_json(Path(self.c['state_dir']) / 'status.json')['deliveryFailures'], 1)
        sent = self.delivery_path.read_text()
        subprocess.run(args, capture_output=True, text=True, check=True)
        self.assertEqual(self.delivery_path.read_text(), sent)
        self.assertNotIn(SENTINEL, sent + result.stdout + result.stderr)

    def test_delivery_bounds_cannot_be_loosened(self):
        path = self.root / 'config.toml'
        path.write_text('[rate_limits]\ncoalesce = 0\nhourly = 100\nreminder = 1\n')
        c = a.config(path)
        self.assertEqual(c['rate_limits'], {'coalesce': 120, 'hourly': 6, 'reminder': 7200})


if __name__ == '__main__':
    unittest.main(verbosity=2)
