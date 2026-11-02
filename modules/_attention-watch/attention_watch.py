#!/usr/bin/env python3
"""Host-local observation and bounded operator escalation; no agent control."""

import argparse
import datetime as dt
import fcntl
import fnmatch
import json
import math
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time
import tomllib
from urllib.parse import urlsplit


class Unavailable(Exception):
    """An observation failed. Never retain external error text."""


def stamp(value):
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value / 1000 if value > 100_000_000_000 else value
    if isinstance(value, str):
        try:
            return dt.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()
        except ValueError:
            pass
    raise Unavailable()


def number(value):
    if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or value < 0:
        raise Unavailable()
    return value


def duration(text):
    parts = re.findall(r'(\d+(?:\.\d+)?)\s*(ms|s|m|h|d)', text)
    if not parts:
        raise Unavailable()
    return sum(float(n) * {'ms': .001, 's': 1, 'm': 60, 'h': 3600, 'd': 86400}[u] for n, u in parts)


def text_age(text, prefix):
    match = re.search(prefix + r'\s+((?:\d+(?:\.\d+)?\s*(?:ms|s|m|h|d)\s*)+)', text)
    return duration(match[1]) if match else None


def alive(pid):
    try:
        pid = int(pid)
        if pid <= 0:
            return False
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except (ValueError, TypeError, ProcessLookupError):
        return False


def read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        raise Unavailable() from None


def command(args, structured=True, allow_partial=False, timeout=20):
    # stderr may contain credentials, message IDs, command lines or prompts.
    # Do not propagate it, including through an exception traceback.
    try:
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, timeout=timeout, check=False)
        if result.returncode not in ((0, 4) if allow_partial else (0,)):
            raise Unavailable()
        if not structured:
            return result.stdout
        data = json.loads(result.stdout)
        if 'outcome' in data and data['outcome'] not in ('ok', 'no-op', 'partial'):
            raise Unavailable()
        if data.get('completeness') == 'partial' and not allow_partial:
            raise Unavailable()
        return data.get('result', data)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        raise Unavailable() from None


def validate_server(value):
    if value is None:
        return None
    try:
        if not isinstance(value, str) or not value or any(ch.isspace() for ch in value):
            raise ValueError()
        url = urlsplit(value)
        if url.scheme not in ('nats', 'tls', 'ws', 'wss') or not url.hostname:
            raise ValueError()
        url.port  # Reject malformed/out-of-range ports, without echoing the URL.
    except ValueError:
        raise ValueError('invalid server URL') from None
    return value


def config(path=None, server=None):
    xdg = Path(os.environ.get('XDG_STATE_HOME', '~/.local/state')).expanduser()
    defaults = {
        'space': 'default', 'workspace_root': str(Path.home()),
        'state_dir': str(xdg / 'agentic-attention-watch'),
        'snapshot_dir': None, 'ci_dir': str(xdg / 'pi-ci-watch'),
        'admin_creds': None, 'server': None, 'dry_run': False, 'host': None, 'notify_seat': None,
        'pending_per_poll': 16, 'ci_lookback': 86400,
        'thresholds': {'broker': 900,
                       'rate_limit': 600, 'approval': 900, 'input': 900,
                       'working': 1800, 'herdr': 600, 'git': 1200, 'snapshot': 180},
        'rate_limits': {'coalesce': 120, 'hourly': 6, 'reminder': 7200},
    }
    if path:
        try:
            raw = Path(path).read_bytes()
            data = json.loads(raw) if str(path).endswith('.json') else tomllib.loads(raw.decode())
        except (OSError, ValueError):
            raise ValueError('cannot read TOML/JSON config') from None
        if set(data) - set(defaults):
            raise ValueError('unknown config key')
        for key, val in data.items():
            if key in ('thresholds', 'rate_limits'):
                if set(val) - set(defaults[key]):
                    raise ValueError('unknown threshold or rate limit')
                defaults[key].update(val)
            else:
                defaults[key] = val
    c = defaults
    notify_seat = c['notify_seat']
    if notify_seat is not None:
        if (not isinstance(notify_seat, dict) or set(notify_seat) - {'name', 'pattern', 'local'}
                or len(set(notify_seat) & {'name', 'pattern'}) != 1
                or not isinstance(notify_seat.get('local', False), bool)):
            raise ValueError('invalid notify_seat config')
        selector = 'name' if 'name' in notify_seat else 'pattern'
        if not isinstance(notify_seat[selector], str) or not notify_seat[selector].strip():
            raise ValueError('invalid notify_seat config')
    c['server'] = validate_server(server if server is not None else c['server'] if c['server'] is not None else os.environ.get('AGENTIC_COTAL_SERVER'))
    if not isinstance(c['space'], str) or not re.fullmatch(r'[A-Za-z0-9_-]+', c['space']):
        raise ValueError('space must be a simple nonempty name')
    c['snapshot_dir'] = c['snapshot_dir'] or str(xdg / 'cotal-seat' / c['space'])
    c['admin_creds'] = c['admin_creds'] or os.environ.get('AGENTIC_COTAL_ADMIN_CREDS') or f'~/.local/share/cotal/{c["space"]}/attention-watch/admin.creds'
    if c['host'] is not None and (not isinstance(c['host'], str) or not c['host']):
        raise ValueError('host must be a nonempty string')
    if not isinstance(c['pending_per_poll'], int) or isinstance(c['pending_per_poll'], bool) or not 1 <= c['pending_per_poll'] <= 100:
        raise ValueError('pending_per_poll must be an integer from 1 to 100')
    if number(c['ci_lookback']) == 0:
        raise ValueError('ci_lookback must be positive')
    for key in ('workspace_root', 'state_dir', 'snapshot_dir', 'ci_dir', 'admin_creds'):
        c[key] = str(Path(c[key]).expanduser().absolute())
    for section in ('thresholds', 'rate_limits'):
        for val in c[section].values():
            try:
                number(val)
            except Unavailable:
                raise ValueError('thresholds and rate limits must be nonnegative numbers') from None
    # Configuration may tighten delivery, never loosen the approved bounds.
    c['rate_limits']['coalesce'] = max(120, c['rate_limits']['coalesce'])
    c['rate_limits']['hourly'] = min(6, c['rate_limits']['hourly'])
    c['rate_limits']['reminder'] = max(7200, c['rate_limits']['reminder'])
    return c


def resolve_notify_seat(c, seats, snapshots):
    """Resolve notification routing for this watcher instance on this host only.

    This DM destination is not exclusive, not a transfer, and not authority:
    it conveys no human-contact, ask_user or approval ownership. Each host's
    watcher can validly route to a different seat. A name/glob match plus a
    live local snapshot proves only a matching, live, local candidate, not
    identity/auth proof, revocation of an old session or approval validity.
    Snapshots are local liveness evidence only.
    """
    notify_seat = c['notify_seat']
    if notify_seat is None:
        return (seats[0], 'single live seat') if len(seats) == 1 else (
            None, 'no live seat' if not seats else 'multiple live seats')
    matches = [name for name in seats
               if (name == notify_seat['name'] if 'name' in notify_seat else
                   fnmatch.fnmatchcase(name, notify_seat['pattern']))
               and (not notify_seat.get('local', False) or name in snapshots)]
    if len(matches) == 1:
        return matches[0], 'selected contact resolved'
    return None, 'selected contact absent' if not matches else 'selected contact ambiguous'


def credential_available(c):
    try:
        info = Path(c['admin_creds']).lstat()
    except FileNotFoundError:
        return False
    except OSError:
        raise ValueError('admin credential metadata unavailable; refusing to start') from None
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
        raise ValueError('admin credential must be a regular file owned by this user with mode exactly 0600; refusing to start')
    # Metadata only. This process never opens or reads the credential.
    return True


class Watcher:
    def __init__(self, c, state=None, clock=time.time, interval=60):
        self.c = c
        self.state = state if state is not None else {'events': {}, 'sent': [], 'resolved': [], 'seen': {}}
        self.state.update(schema='agentic.attention-watch.state/1', intervalSeconds=interval)
        self.state.setdefault('broker_progress', {})
        self.state.setdefault('brokerCoverageSeconds', interval)
        self.interval = interval
        self.clock = clock
        self.live_names = set()
        self.pending_checked = set()
        self.findings = []
        self.sources = {}
        self.seats = []
        self.local_names = set()
        self.notify_seat_snapshots = set()
        self.context = {}
        self.sessions = {}
        self.current_source = None
        self.observations = {}

    def add(self, kind, subject, facts, threshold, since=None, human=False):
        self.findings.append({'kind': kind, 'subject': subject, 'facts': facts,
                              'threshold': threshold, 'since': since, 'human': human,
                              'source': self.current_source,
                              'suggested_owner_action': 'operator: inspect the owning session/pane; decide manually'})

    def unavailable(self, source):
        self.sources[source] = 'unavailable'
        self.add('source-unavailable', source, 'observation unavailable (details withheld)',
                 'readable source', human=True)

    def continuous(self, key, active, now):
        if not active:
            self.state['seen'].pop(key, None)
            return now
        return self.state['seen'].setdefault(key, now)

    def presence(self, now):
        data = command(['cotal', 'endpoints', '--space', self.c['space'], '--json'])
        if data.get('kind') != 'live-presence' or not isinstance(data.get('items'), list):
            raise Unavailable()
        items = [p for p in data['items'] if p.get('kind') == 'agent'
                 and p.get('reportedStatus') in ('idle', 'waiting', 'working')]
        self.seats = [p['name'] for p in items if p.get('role') == 'seat']
        all_count = len(items)
        # Advisory host tags may narrow observations, never seat discovery.
        # Untagged agents stay included; snapshots are optional enrichment.
        host = self.c['host']
        items = [p for p in items if host is None or
                 (p.get('card', {}).get('meta', p.get('meta', {})) or {}).get('host') in (None, host)]
        self.live_names = {p['name'] for p in items}
        self.observations['S1'] = {'livePeers': all_count, 'observedPeers': len(items)}
        for p in items:
            name = p['name']
            ages = str(p.get('facts', {}).get('ages', ''))
            condition = str(p.get('facts', {}).get('condition', ''))
            text = condition + ' ' + ages + ' ' + str(p.get('activityAge', ''))
            for kind in ('rate_limit', 'approval', 'input'):
                age = text_age(text, re.escape(kind) + r' for')
                if age is not None and age >= self.c['thresholds'][kind]:
                    self.add(kind, name, f'{kind} age={int(age)}s', self.c['thresholds'][kind])
            active = text_age(text, 'active')
            if p['reportedStatus'] == 'working' and active is not None and active >= self.c['thresholds']['working']:
                self.add('working-stale', name, f'last active age={int(active)}s', self.c['thresholds']['working'])
        return items

    def pending(self, items, now):
        self.state['brokerCoverageSeconds'] = self.interval * max(1, math.ceil(len(items) / self.c['pending_per_poll']))
        if not credential_available(self.c):
            self.sources['S2'] = 'unavailable: admin credential absent (optional)'
            return
        self.sources['S2'] = 'available; redelivery unavailable in Cotal 0.91; candidate ages bounded'
        self.observations['S2'] = {'inspectedPeers': 0, 'deferredPeers': len(items), 'suppressedPeers': 0}
        items = sorted(items, key=lambda p: p['name'])
        start = self.state.get('pending_cursor', 0) % max(1, len(items))
        selected = (items[start:] + items[:start])[:self.c['pending_per_poll']]
        deadline = time.monotonic() + self.interval
        for p in selected:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            name = p['name']
            self.state['pending_cursor'] = (items.index(p) + 1) % len(items)
            self.pending_checked.add(name)
            data = command(['cotal', 'pending', name, '--space', self.c['space'],
                            '--creds', self.c['admin_creds'], '--json'] +
                           (['--server', self.c['server']] if self.c['server'] else []),
                           allow_partial=True, timeout=min(20, remaining))
            now = self.clock()  # Timestamp this agent's completed read, not the poll start.
            self.observations['S2']['inspectedPeers'] += 1
            self.observations['S2']['deferredPeers'] -= 1
            # Strict projection: no IDs, sender, subjects, bodies, durable names,
            # warnings or external diagnostics escape this function.
            pending = number(data.get('pending'))
            ack = number(data.get('ackPending'))
            count = pending + ack
            floor = number(data.get('ackFloor'))
            delivered = number(data.get('delivered'))
            if int(floor) != floor or int(delivered) != delivered:
                raise Unavailable()
            floor, delivered = int(floor), int(delivered)
            progress = self.state.setdefault('broker_progress', {})
            previous = progress.get(name)
            if count == 0:
                progress.pop(name, None)
                since = now
            elif previous is None or previous['floor'] != floor:
                progress[name] = {'floor': floor, 'since': now, 'observedAt': now}
                since = now
            else:
                since = previous['since']
                previous['observedAt'] = now
            candidate_ages = [max(0, now - stamp(row['ts'])) for row in data.get('candidates', [])
                              if isinstance(row, dict) and 'ts' in row]
            candidate_age = max(candidate_ages, default=0)
            local_age = now - since
            active = text_age(' '.join(str(v) for v in (
                p.get('facts', {}).get('condition', ''), p.get('facts', {}).get('ages', ''),
                p.get('activityAge', ''))), 'active')
            busy = (p['reportedStatus'] == 'working' and active is not None
                    and active < self.c['thresholds']['working'])
            if count and local_age >= self.c['thresholds']['broker'] and busy:
                self.observations['S2']['suppressedPeers'] += 1
            elif count and local_age >= self.c['thresholds']['broker']:
                self.add('broker-backlog', name,
                         f'pending={pending}; ackPending={ack}; ackFloor={floor}; delivered={delivered}; unchanged floor with backlog={int(local_age)}s; bounded sample of recent candidates age={int(candidate_age)}s (not the oldest held); redelivery unavailable in this Cotal version',
                         self.c['thresholds']['broker'])

    def snapshots(self, now):
        root = Path(self.c['snapshot_dir'])
        if not root.exists():
            self.sources['S3'] = 'unavailable: no snapshots (extension not enabled?)'
            self.observations['S3'] = {'snapshotFiles': 0}
            return
        if not root.is_dir():
            raise Unavailable()
        paths = sorted(root.glob('*.json'))
        self.observations['S3'] = {'snapshotFiles': len(paths)}
        if not paths:
            self.sources['S3'] = 'unavailable: no snapshots (extension not enabled?)'
        for path in paths:
            data = read_json(path)
            if (not isinstance(data, dict) or data.get('schema') != 'agentic.seat-snapshot/1'
                    or data.get('space') != self.c['space']
                    or not isinstance(data.get('name'), str) or not data['name']
                    or not isinstance(data.get('cwd'), str) or not data['cwd']
                    or not isinstance(data.get('pid'), int) or isinstance(data['pid'], bool)):
                raise Unavailable()
            name = data['name']
            self.local_names.add(name)
            self.context.setdefault(str(Path(data['cwd']).resolve()), set()).add(name)
            if data.get('piSession'):
                self.sessions[data['piSession']] = name
            written = number(stamp(data['writtenAt']))
            age = max(0, now - written)
            live = alive(data['pid'])
            if (live and age <= self.c['thresholds']['snapshot']
                    and Path(data['cwd']).resolve().is_relative_to(Path(self.c['workspace_root']).resolve())):
                self.notify_seat_snapshots.add(name)
            if name in self.live_names and (age > self.c['thresholds']['snapshot'] or not live):
                self.add('snapshot-stale', name, f'seat process gone or wedged; write age={int(age)}s; process alive={live}; presence still live', self.c['thresholds']['snapshot'])
            # Optional enrichment is liveness-only. A null connection is the
            # expected snapshot-writer contract, not a queue-health failure.

    def herdr(self, now):
        data = command(['herdr', 'agent', 'list'])
        if not isinstance(data.get('agents'), list):
            raise Unavailable()
        root = Path(self.c['workspace_root']).resolve()
        self.observations['S4'] = {'workspaceAgents': 0, 'blockedAgents': 0}
        for row in data['agents']:
            cwd = Path(row.get('cwd', '/')).resolve()
            if not cwd.is_relative_to(root):
                continue
            self.observations['S4']['workspaceAgents'] += 1
            pane = row['pane_id']
            # Only retain process PID/cwd, never argv/cmdline/session prompts.
            details = command(['herdr', 'pane', 'process-info', '--pane', pane])
            info = details.get('process_info')
            if not isinstance(info, dict):
                raise Unavailable()
            if not isinstance(info.get('foreground_processes'), list):
                raise Unavailable()
            blocked = row.get('agent_status') in ('blocked', 'waiting', 'input', 'approval')
            self.observations['S4']['blockedAgents'] += int(blocked)
            key = 'herdr:' + pane
            since = self.continuous(key, blocked, now)
            if blocked and now - since >= self.c['thresholds']['herdr']:
                owners = self.context.get(str(cwd), set())
                subject = next(iter(owners)) if len(owners) == 1 else 'pane/' + pane
                self.add('herdr-blocked', subject, f'pane={pane}; blocked observed={int(now-since)}s', self.c['thresholds']['herdr'], human=len(owners) != 1)

    def git(self, now):
        raw = command(['ps', '-axo', 'pid=,etime=,comm='], structured=False)
        self.observations['S5'] = {'gitProcesses': 0, 'overThresholdInWorkspace': 0}
        root = Path(self.c['workspace_root']).resolve()
        for line in raw.splitlines():
            parts = line.strip().split(None, 2)
            if len(parts) != 3 or Path(parts[2]).name not in ('git', 'git-remote-https', 'git-remote-http', 'git-lfs'):
                continue
            self.observations['S5']['gitProcesses'] += 1
            pid = int(parts[0])
            value = parts[1]
            days, _, rest = value.rpartition('-')
            age = int(days or 0) * 86400
            fields = [int(v) for v in rest.split(':')]
            for i, v in enumerate(reversed(fields)):
                age += v * 60 ** i
            if age < self.c['thresholds']['git']:
                continue
            cwd_raw = command(['lsof', '-a', '-p', str(pid), '-d', 'cwd', '-Fn'], structured=False)
            cwds = [Path(v[1:]).resolve() for v in cwd_raw.splitlines() if v.startswith('n')]
            if any(cwd.is_relative_to(root) for cwd in cwds):
                self.observations['S5']['overThresholdInWorkspace'] += 1
                owners = set().union(*(self.context.get(str(cwd), set()) for cwd in cwds))
                self.add('git-hung', 'pid/' + str(pid), f'git elapsed={age}s; cwd under workspace root', self.c['thresholds']['git'],
                         human=not owners or bool(owners.intersection(self.seats)))

    def ci(self, now):
        root = Path(self.c['ci_dir'])
        if not root.is_dir():
            raise Unavailable()
        paths = sorted(root.glob('sessions/*/watches/*/state.json'))
        self.observations['S6'] = {'watchFiles': len(paths), 'pendingWatches': 0, 'ignoredOldWatchStates': 0}
        for path in paths:
            data = read_json(path)
            if 'observedAt' in data and now - stamp(data['observedAt']) > self.c['ci_lookback']:
                self.observations['S6']['ignoredOldWatchStates'] += 1
                continue
            if not (data.get('phase') == 'pending' or
                    (data.get('phase') == 'running' and data.get('lastObservation', {}).get('phase') == 'pending')):
                continue
            self.observations['S6']['pendingWatches'] += 1
            watch = read_json(path.with_name('watch.json'))
            observed = stamp(data['observedAt'])
            # Real watch.json commonly has cadence={}; mirror the installed
            # watcher's defaults (initial 60, maximum 600, floor 30 seconds).
            cadence = watch.get('cadence') or {}
            interval = max(30, number(cadence.get('initialSeconds', 60)), number(cadence.get('maxSeconds', 600)))
            deadline = stamp(watch['deadlineAt'])
            live = alive(data['pid'])
            if now - observed > 3 * interval or not live or now > deadline:
                self.add('ci-watch-stale', 'watch/' + path.parent.name,
                         f'observation age={int(now-observed)}s; pid alive={live}; past deadline={now > deadline}',
                         f'3 x max poll ({3*interval}s), dead pid or expired deadline',
                         human=self.sessions.get(watch.get('owner', {}).get('sessionFile')) in self.seats)

        ignored = self.observations['S6']['ignoredOldWatchStates']
        if ignored:
            self.sources['S6'] = f'available; ignored: {ignored} old watch states'

    def observe(self):
        now = self.clock()
        self.findings, self.sources, self.local_names, self.context, self.sessions = [], {}, set(), {}, {}
        self.observations = {}
        self.notify_seat_snapshots = set()
        self.live_names, self.pending_checked = set(), set()
        self.current_source = 'S1'
        self.sources['S1'] = 'available'
        try:
            items = self.presence(now)
        except (Unavailable, OSError, KeyError, TypeError, ValueError):
            self.seats = []
            items = []
            self.unavailable('S1')
        self.current_source = 'S2'
        try:
            self.pending(items, now)
        except (Unavailable, OSError, KeyError, TypeError):
            self.unavailable('S2')
        for source, read in [('S3', self.snapshots), ('S4', self.herdr), ('S5', self.git), ('S6', self.ci)]:
            self.current_source = source
            self.sources[source] = 'available'
            try:
                read(now)
            except (Unavailable, OSError, KeyError, TypeError, ValueError):
                if source == 'S3':
                    self.notify_seat_snapshots.clear()
                self.unavailable(source)
        return self.findings

    def reconcile(self):
        now = self.clock()
        events = self.state['events']
        current = set()
        for finding in self.findings:
            key = finding['kind'] + ':' + finding['subject']
            current.add(key)
            event = events.get(key)
            if event is None or not event['active']:
                since = max(int(now), int(event['since']) + 1 if event else 0)
                event = {'since': since, 'id': f'{key}:{since}', 'first': now,
                         'last_dm': None, 'notified': False, 'active': True}
                events[key] = event
            finding['since'] = event['since']
            finding['id'] = event['id']
            finding['observedAt'] = now
            event['finding'] = finding
        for key, event in events.items():
            if key not in current and event['active']:
                source = event['finding'].get('source')
                if source and str(self.sources.get(source, '')).startswith('unavailable') and event['finding']['kind'] != 'source-unavailable':
                    continue  # An unreadable source is unknown, never a resolution.
                if source == 'S2' and event['finding']['subject'] in self.live_names and event['finding']['subject'] not in self.pending_checked:
                    continue  # Deferred by per-poll cap, not proven resolved.
                event['active'] = False
                if event['last_dm'] is not None or event['notified']:
                    self.state['resolved'].append(event['id'])
        return events

    def deliver(self, dry_run=False):
        now = self.clock()
        events = self.reconcile()
        rates = self.c['rate_limits']
        self.state['sent'] = [v for v in self.state['sent'] if now - v < 3600]
        notify_seat, notify_seat_reason = resolve_notify_seat(self.c, self.seats, self.notify_seat_snapshots)
        candidates = []
        for event in events.values():
            if not event['active']:
                continue
            finding = event['finding']
            if finding.get('source') and str(self.sources.get(finding['source'], '')).startswith('unavailable') and finding['kind'] != 'source-unavailable':
                continue
            if finding.get('source') == 'S2' and finding['kind'] != 'source-unavailable' and finding['subject'] not in self.pending_checked:
                continue
            human = finding['human'] or notify_seat is None or finding['subject'] in self.seats
            # Once routed to a human, this transition is never subsequently DMed.
            if event['notified']:
                continue
            if human:
                if not event['notified']:
                    candidates.append(('notification', event))
            elif event['last_dm'] is None or now - event['last_dm'] >= rates['reminder']:
                candidates.append(('dm', event))
        deliveries = []
        for route in ('notification', 'dm'):
            selected = [e for r, e in candidates if r == route]
            if not selected:
                continue
            if not dry_run and now - min(e['first'] if e['last_dm'] is None else e['last_dm'] + rates['reminder'] for e in selected) < rates['coalesce']:
                continue
            if route == 'dm' and len(self.state['sent']) >= rates['hourly']:
                continue
            lines = ['Agentic attention (observe only; no action taken)']
            if route == 'notification' and notify_seat is None:
                lines.append('notify_seat: ' + notify_seat_reason)
            for event in selected:
                f = event['finding']
                lines.append(f"kind={f['kind']}; subject={f['subject']}; observedAt={f['observedAt']}; facts={f['facts']}; threshold={f['threshold']}; id={event['id']}; suggested owner/action={f['suggested_owner_action']}")
            if route == 'dm' and self.state['resolved']:
                lines.append('resolved since last: ' + ', '.join(self.state['resolved']))
            target = notify_seat if route == 'dm' else 'human'
            deliveries.append({'route': route, 'target': target, 'text': '\n'.join(lines)})
            if not dry_run:
                for event in selected:
                    if route == 'dm':
                        event['last_dm'] = now
                    else:
                        event['notified'] = True
                if route == 'dm':
                    self.state['sent'].append(now)
                    self.state['resolved'] = []
        return deliveries

    def report(self):
        resolved, reason = resolve_notify_seat(self.c, self.seats, self.notify_seat_snapshots)
        notify_seat = self.c['notify_seat']
        return {'notifySeat': {'selector': 'unset' if notify_seat is None else 'name' if 'name' in notify_seat else 'pattern',
                            'local': bool(notify_seat and notify_seat.get('local', False)),
                            'resolved': resolved, 'reason': reason},
                'observedAt': self.clock(), 'sources': self.sources, 'observations': self.observations, 'liveSeats': self.seats,
                'localSubjects': sorted(self.local_names), 'findings': self.findings,
                'pending': sum(e['active'] and e['last_dm'] is None and not e['notified'] for e in self.state['events'].values())}


def save(path, data, now=None):
    if data.get('schema') == 'agentic.attention-watch.state/1':
        data['writtenAt'] = float(time.time() if now is None else now)
    tmp = path.with_suffix('.tmp')
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, 'w') as handle:
        json.dump(data, handle, sort_keys=True)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)
    directory = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('run', 'status'), nargs='?', default='run')
    parser.add_argument('--config')
    parser.add_argument('--admin-creds', help='override config/env admin credential pathname')
    parser.add_argument('--server', help='override config/env admin broker URL')
    parser.add_argument('--interval', type=float, default=60)
    parser.add_argument('--once', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args(argv)
    try:
        c = config(args.config, server=args.server)
        if args.admin_creds:
            c['admin_creds'] = str(Path(args.admin_creds).expanduser().absolute())
        credential_available(c)  # Refuse before opening state or running any command.
        root = Path(c['state_dir'])
        if args.command == 'status':
            try:
                report = read_json(root / 'status.json')
            except Unavailable:
                report = {'status': 'not yet observed', 'sources': {'S2': 'available' if credential_available(c) else 'unavailable: admin credential absent (optional)'}}
            if not credential_available(c):
                report.setdefault('sources', {})['S2'] = 'unavailable: admin credential absent (optional)'
            print(json.dumps(report, indent=2 if args.json else None))
            return 0
        if not math.isfinite(args.interval) or args.interval <= 0:
            raise ValueError('interval must be positive')
        dry = args.dry_run or c['dry_run']
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        with (root / 'lock').open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('another watcher holds this state directory') from None
            state_path = root / 'state.json'
            state = read_json(state_path) if state_path.exists() else None
            watcher = Watcher(c, state, interval=args.interval)
            while True:
                watcher.observe()
                deliveries = watcher.deliver(dry)
                report = watcher.report()
                if not dry:
                    # Reserve delivery IDs durably BEFORE invoking external commands.
                    # Ambiguous failures are never blindly retried (at-most-once attempt).
                    save(state_path, watcher.state)
                    failures = 0
                    for delivery in deliveries:
                        command_args = (['cotal', 'send', '--space', c['space'], '-t', delivery['target'], delivery['text']]
                                        if delivery['route'] == 'dm' else
                                        ['herdr', 'notification', 'show', 'Agentic attention', '--body', delivery['text'], '--sound', 'none'])
                        try:
                            command(command_args, structured=False)
                        except Unavailable:
                            failures += 1
                    report['deliveryFailures'] = failures
                    save(root / 'status.json', report)
                else:
                    print(json.dumps({'dryRun': True, 'report': report, 'wouldSend': deliveries}, indent=2))
                if args.once:
                    return 0
                time.sleep(args.interval)
    except (ValueError, Unavailable, OSError, KeyError, TypeError):
        # Never echo arbitrary config values, source errors or payload data.
        message = 'watcher state/config unavailable; refusing to start'
        exc = sys.exc_info()[1]
        if isinstance(exc, ValueError) and str(exc) in {
            'admin credential must be a regular file owned by this user with mode exactly 0600; refusing to start',
            'admin credential metadata unavailable; refusing to start',
            'another watcher holds this state directory', 'interval must be positive'}:
            message = str(exc)
        print('agentic-attention-watch: ' + message, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
