"""Disposable integration fixtures. Every external process is a PATH fake."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

recover, reader = sys.argv[1:]
FAKE = r'''#!/usr/bin/env python3
import json,os,pathlib,sys
c=json.loads(pathlib.Path(os.environ['FIXTURE']).read_text())
a=sys.argv[1:]; tool=pathlib.Path(sys.argv[0]).name
result={}
if tool=='cotal':
 if a[0]=='pending':
  assert (a[a.index('--server')+1] if '--server' in a else None)==c.get('server')
  result=c.get('pendingResult',{'pending':3,'ackPending':2,'ackFloor':{'stream_seq':5,'consumer_seq':5},'delivered':{'stream_seq':7,'consumer_seq':7},'ids':['DO NOT EMIT']})
 elif a[0]=='endpoints':
  if c.get('meshFailure'): sys.exit(1)
  result={'items':c['presence']}
 if a[0]!='pending': assert '--server' not in a
 partial=a[0] in c.get('partial',[])
 print(json.dumps({'outcome':'partial' if partial else 'ok','completeness':'partial' if partial else 'complete','result':result}))
 sys.exit(c.get('exit',4) if partial else 0)
elif tool=='herdr':
 if a[:2]==['agent','list']: result={'agents':c['agents']}
 elif a[:2]==['workspace','list']: result={'workspaces':[{'workspace_id':'w1','worktree':{'checkout_path':c['worktree']}}]}
 elif a[:2]==['pane','list']: result={'panes':[{'pane_id':'w1:p1','workspace_id':'w1','cwd':c['worktree']}]}
 elif a[:2]==['pane','process-info']: result={'process_info':c['process']}
 print(json.dumps({'result':result}))
elif tool=='ps':
 if a[:1]==['-axo'] and c.get('git'): print('2147483646 21:00 /usr/bin/git')
 elif a[:1]==['-p']: print(c['worktree'])
elif tool=='git':
 if 'rev-parse' in a: print('abc123')
 elif 'branch' in a: print('feat/fixture')
 elif 'log' in a: print('abc123 fixture commit')
 elif 'status' in a: print(' M changed.txt')
elif tool=='workbench-worker-start':
 pathlib.Path(os.environ['ARGV']).write_text(json.dumps(a))
 print(json.dumps({'status':'started','session':'/new-session.jsonl'}))
'''
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp)
    bin = temp / 'bin'
    bin.mkdir()
    for name in ('cotal', 'herdr', 'ps', 'git', 'lsof', 'workbench-worker-start'):
        file = bin / name
        file.write_text(FAKE)
        file.chmod(0o755)
    worktree = temp / 'worktree'
    worktree.mkdir()
    session = temp / 'old-session.jsonl'
    session.write_text('history untouched\n')
    assignment = temp / 'assignment.md'
    assignment.write_text('Outstanding fixture task\n')
    config = temp / 'config.json'
    argv = temp / 'argv.json'
    env = {**os.environ, 'PATH': str(bin)+os.pathsep+os.environ['PATH'], 'XDG_STATE_HOME': str(temp / 'state'),
           'FIXTURE': str(config), 'ARGV': str(argv), 'COTAL_SPACE': 'fixture', 'AGENTIC_COTAL_ADMIN_CREDS': str(temp/'absent'), 'AGENTIC_COTAL_SERVER': ''}
    snapshot_file = temp / 'state/cotal-seat/fixture/worker.json'
    snapshot_file.parent.mkdir(parents=True)
    def setup(kind='dead'):
        data = {'schema':'agentic.seat-snapshot/1','space':'fixture','name':'worker','instanceId':'local.test',
                'pid':2147483647 if kind=='dead' else os.getpid(),'piSession':str(session),'cwd':str(worktree),
                'writtenAt':time.time()*1000,'connection':None,'connectionError':'observation unavailable'}
        c = {'worktree':str(worktree), 'presence':[], 'agents':[],
             'process':{'shell_pid':42,'foreground_processes':[{'pid':42,'name':'nu','argv0':'nu'}]}}
        if kind!='dead':
            c['presence']=[{'name':'worker','reportedStatus':'working','facts':{'ages':'active 2m ago · unchanged for 40m'}}]
            c['agents']=[{'pane_id':'w1:p1','agent':'pi','agent_status':'working','cwd':str(worktree)}]
            c['process']['foreground_processes']=[{'pid':os.getpid(),'name':'pi','argv0':'/bin/pi','cmdline':'PRIVATE ASSIGNMENT'}]
        if kind=='queue-stalled':
            data['connection']={'automaticCount':1,'automaticQueueStalledForMs':900000}
        elif kind=='hung-process': c['presence'][0]['facts']['ages']='active 3h ago'
        elif kind=='blocked':
            c['presence'][0]['reportedStatus']='waiting'
            c['presence'][0]['facts']['ages']='unchanged for 10m'
            c['agents'][0]['agent_status']='blocked'
        elif kind=='unknown': c['presence'][0]['facts']['ages']='unchanged for 40m'
        config.write_text(json.dumps(c)); snapshot_file.write_text(json.dumps(data))
        return c,data
    def call(*extra, expected=0):
        p=subprocess.run([recover,'--worker','worker','--worktree',str(worktree),'--json',*extra],env=env,text=True,capture_output=True)
        assert p.returncode==expected,(p.returncode,p.stdout,p.stderr)
        assert 'PRIVATE ASSIGNMENT' not in p.stdout
        return json.loads(p.stdout)
    for kind in ('progressing','queue-stalled','blocked','hung-process','dead','unknown'):
        setup(kind)
        row=call()
        assert row['class']==kind,(kind,row)
        print('class',kind,'PASS')
    c,data=setup('progressing'); c['git']=True; config.write_text(json.dumps(c))
    row=call(); assert row['class']=='hung-process' and row['evidence']['gitProcesses'][0]['etime']=='21:00'
    assert row['suggestedCommands']; print('git >=20m PASS')
    for kind in ('resume','replace'):
        setup('progressing'); call('--action',kind,'--assignment',str(assignment),expected=2)
        print(kind,'live pid refusal PASS')
        c,data=setup(); c['agents']=[{'cwd':str(worktree)},{'cwd':str(worktree)}]; config.write_text(json.dumps(c))
        assert call('--action',kind,'--assignment',str(assignment),expected=2)['evidence']['duplicate']
        print(kind,'two-agent refusal PASS')
        c,data=setup(); c['process']={}; config.write_text(json.dumps(c))
        call('--action',kind,'--assignment',str(assignment),expected=2)
        print(kind,'unproven process refusal PASS')
    c,data=setup(); c['meshFailure']=True; config.write_text(json.dumps(c))
    call('--action','resume',expected=2); print('unproven presence refusal PASS')
    c,data=setup(); data['schema']='future/2'; snapshot_file.write_text(json.dumps(data))
    call('--action','resume',expected=2); print('unknown schema fencing refusal PASS')
    c,data=setup(); data['cwd']='/different-checkout'; snapshot_file.write_text(json.dumps(data))
    call('--action','resume',expected=2); print('mismatched snapshot binding refusal PASS')
    c,data=setup('queue-stalled'); data['connection']['automaticQueueStalledForMs']=899999; snapshot_file.write_text(json.dumps(data))
    assert call()['class']=='progressing'; print('queue threshold just below 15m PASS')
    setup(); row=call('--action','resume','--assignment',str(assignment))
    expected=['--pane','w1:p1','--worktree',str(worktree),'--','pi-worker','--name','worker-r1','--cwd',str(worktree),'--space','fixture','--resume',str(session)]
    assert json.loads(argv.read_text())==expected
    assert row['attempt']['piSession']=='/new-session.jsonl'
    assert 'resumed as a fork of' in row['followUpDM']
    assert session.read_text()=='history untouched\n'
    call('--action','resume',expected=2); print('resume exact argv + no blind repeat PASS')
    for file in (temp/'state/agentic-worker-recover').glob('*.json'): file.unlink()
    row=call('--action','replace','--assignment',str(assignment))
    actual=json.loads(argv.read_text())
    handover=actual[-1]
    expected=expected[:-2]+['--prompt-file',handover]
    assert actual==expected,(actual,expected)
    text=Path(handover).read_text()
    assert all(t in text for t in ('Outstanding fixture task','abc123','feat/fixture',' M changed.txt'.strip(),'fixture commit'))
    assert Path(handover).stat().st_mode & 0o777==0o600
    print('replace exact argv + handover PASS')
    # Reader staleness: fresh, old, dead, unknown schema, malformed.
    setup('progressing')
    def rows():
        return json.loads(subprocess.check_output([reader,'--space','fixture','--name','worker','--json'],env=env,text=True))
    assert rows()[0]['stale'] is False
    data=json.loads(snapshot_file.read_text()); data['writtenAt']-=181000; snapshot_file.write_text(json.dumps(data))
    assert rows()[0]['stale'] is True
    setup(); assert rows()[0]['stale'] is True
    data['schema']='future/2'; snapshot_file.write_text(json.dumps(data)); assert rows()[0]['available'] is False
    snapshot_file.write_text('{'); assert rows()[0]['available'] is False
    print('reader fresh/old/dead/unknown/malformed PASS')
    # Admin credentials are optional, private, and whitelisted observations only.
    setup(); creds=temp/'admin.creds'; creds.write_text('fixture, not a credential'); creds.chmod(0o644)
    assert call('--admin-creds',str(creds))['evidence']['queue']['available'] is False
    creds.chmod(0o600)
    row=call('--admin-creds',str(creds)); assert row['evidence']['queue']['available'] is True
    assert 'DO NOT EMIT' not in json.dumps(row)
    symlink=temp/'linked.creds'; symlink.symlink_to(creds)
    assert call('--admin-creds',str(symlink))['evidence']['queue']['available'] is False
    print('admin creds mode/symlink + queue single sample sanitization PASS')
    # Off-registry routing and bounded partial pending reads only.
    c,data=setup()
    sample={'pending':3,'ackPending':2,'ackFloor':5,'delivered':7,'ids':['DO NOT EMIT']}
    for server in (None,'tls://broker.invalid:4222'):
        c.update(server=server,partial=['pending'],pendingResult=sample)
        config.write_text(json.dumps(c))
        row=call('--admin-creds',str(creds),*(['--server',server] if server else []))
        queue=row['evidence']['queue']
        assert queue['available'] and queue['completeness']=='partial' and queue['ackFloor']==5 and queue['pending']==3,queue
        assert 'DO NOT EMIT' not in json.dumps(row) and 'broker.invalid' not in json.dumps(row)
    env['AGENTIC_COTAL_SERVER']=c['server']
    assert call('--admin-creds',str(creds))['evidence']['queue']['available']
    row=call('--admin-creds',str(creds),'--server',c['server'])
    env['AGENTIC_COTAL_SERVER']='nats://ignored.invalid:4222'
    assert call('--admin-creds',str(creds),'--server',c['server'])['evidence']['queue']['available']
    env['AGENTIC_COTAL_SERVER']=''
    print('pending exit 4 partial, server absent/flag/env precedence, sanitization PASS')
    c['server']=None
    for field in ('pending','ackPending','ackFloor'):
        for value in (None,True,'5',{},-1,float('nan'),float('inf')):
            c['pendingResult']={**sample,field:value}; config.write_text(json.dumps(c))
            assert not call('--admin-creds',str(creds))['evidence']['queue']['available']
    c['pendingResult']=sample
    for code in (0,2,5):
        c['exit']=code; config.write_text(json.dumps(c))
        assert not call('--admin-creds',str(creds))['evidence']['queue']['available']
    c.pop('exit'); c['partial']=['endpoints']; config.write_text(json.dumps(c))
    row=call('--admin-creds',str(creds),'--action','resume',expected=2)
    assert not row['evidence']['presenceComplete']
    print('partial malformed pending and partial endpoints refused PASS')
    # Fixed shared BPH-81 state contract: seconds (not snapshot milliseconds).
    setup('progressing')
    watch = temp / 'state/agentic-attention-watch/state.json'
    watch.parent.mkdir()
    def watch_state(**changes):
        state = {'schema':'agentic.attention-watch.state/1','writtenAt':time.time(),
                 'intervalSeconds':60,'brokerCoverageSeconds':60,
                 'broker_progress':{'worker':{'floor':5,'since':time.time()-901,'observedAt':time.time()}},
                 'ignored_secret':'NEVER COPY WATCHER PRIVATE FIELDS'}
        state.update(changes)
        watch.write_text(json.dumps(state)); watch.chmod(0o600)
    watch_state()
    row=call(); assert row['class']=='queue-stalled' and row['evidence']['watcherQueue']['stalled'] is True
    assert 'NEVER COPY' not in json.dumps(row)
    print('watch state fresh stalled + ignored fields PASS')
    watch_state(broker_progress={})
    row=call(); assert row['evidence']['watcherQueue']['stalled'] is False and row['class']=='progressing'
    watch_state(broker_progress={'worker':{'floor':5,'since':time.time()-899,'observedAt':time.time()}})
    assert call()['evidence']['watcherQueue']['stalled'] is False
    print('watch state fresh no backlog and below threshold PASS')
    watch_state(broker_progress={'worker':{'floor':5,'since':time.time()-901,'observedAt':time.time()-121}})
    row=call(); assert row['evidence']['watcherQueue']['available'] is False
    assert row['evidence']['watcherQueue']['stalled'] is None
    assert row['evidence']['watcherQueue']['reason']=='queue: unknown (watcher sample too old)'
    assert row['class']=='progressing'
    print('watch state fresh file but old per-agent sample unavailable PASS')
    watch_state(writtenAt=time.time()-181)
    row=call(); assert row['evidence']['watcherQueue']['available'] is False
    assert row['evidence']['watcherQueue']['stalled'] is None
    assert 'watcher state stale' in row['evidence']['watcherQueue']['reason']
    print('watch state stale unavailable PASS')
    watch_state(schema='future/2')
    assert call()['evidence']['watcherQueue']['available'] is False
    print('watch state wrong schema unavailable PASS')
    for changes in ({'intervalSeconds':0},{'writtenAt':True},{'broker_progress':{'worker':{'floor':True,'since':1}}}):
        watch_state(**changes)
        assert call()['evidence']['watcherQueue']['available'] is False
    print('watch state malformed facts unavailable PASS')
    watch_state()
    override=temp/'watch-override.json'; watch.rename(override)
    assert call()['evidence']['watcherQueue']['available'] is False
    assert call('--watch-state',str(override))['class']=='queue-stalled'
    print('watch state override PASS')
