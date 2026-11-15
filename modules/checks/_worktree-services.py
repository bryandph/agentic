"""Offline fixtures: only the fake Herdr can be invoked."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

setup, attach_setup, teardown, services, helper = sys.argv[1:]
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    main, tree = root / "main", root / "tree"
    main.mkdir()
    env = dict(os.environ, HOME=str(root), XDG_STATE_HOME=str(root / "state"),
               COTAL_NAME="fixture-owner", TEST_MAIN=str(main), TEST_LOG=str(root / "herdr-log"))
    def call(*args, expected=0):
        p = subprocess.run(args, env=env, text=True, capture_output=True)
        assert p.returncode == expected, (args, p.returncode, p.stdout, p.stderr)
        return p.stdout
    call("git", "init", "-q", str(main))
    call("git", "-C", str(main), "config", "user.email", "fixture@example.invalid")
    call("git", "-C", str(main), "config", "user.name", "Fixture")
    call("git", "-C", str(main), "commit", "-qm", "init", "--allow-empty")
    call("git", "-C", str(main), "worktree", "add", "-qb", "side", str(tree))
    gitdir = Path(call("git", "-C", str(tree), "rev-parse", "--absolute-git-dir").strip())
    binary = root / "bin"
    binary.mkdir()
    fake = binary / "herdr"
    fake.write_text('''#!/usr/bin/env python3
import json,os,subprocess,sys
args=sys.argv[1:]
with open(os.environ['TEST_LOG'],'a') as f: f.write(json.dumps(args)+'\\n')
if args[:2]==['workspace','list']:
    value={'workspaces':[] if os.environ.get('TEST_NO_WORKSPACE') else [{'workspace_id':'main-ws','worktree':{'checkout_path':os.environ['TEST_MAIN']}}]}
elif args[:2]==['tab','create']:
    value={'tab':{'tab_id':'main-ws:t1'},'root_pane':{'pane_id':'main-ws:p1'}}
elif args[:2]==['pane','run']:
    if not os.environ.get('TEST_FAIL_START'):
        p=subprocess.Popen(['bash','-c',args[3]],cwd=os.environ['TEST_MAIN'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
        open(os.environ['TEST_PID'],'w').write(str(p.pid))
    value={'type':'ok'}
elif args[:2]==['pane','get']:
    if os.environ.get('TEST_PANE_ERROR'):
        print(os.environ['TEST_PANE_ERROR'],file=sys.stderr); sys.exit(1)
    value={'pane':{'pane_id':args[2]}}
elif args[:2]==['tab','close']:
    if os.environ.get('TEST_TAB_ERROR'):
        print(os.environ['TEST_TAB_ERROR'],file=sys.stderr); sys.exit(1)
    value={'type':'ok'}
else: raise Exception(args)
print(json.dumps({'result':value}))
''')
    fake.chmod(0o755)
    env['PATH'] = str(binary) + os.pathsep + env['PATH']
    listener = root / "listen.py"
    listener.write_text('''import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(('127.0.0.1',int(sys.argv[1]))); s.listen()
while True:
 c,_=s.accept(); c.close()
''')
    env.update(TEST_LISTENER=str(listener), TEST_PID=str(root / 'pid'))
    def port():
        with socket.socket() as s:
            s.bind(('127.0.0.1',0))
            env['TEST_PORT'] = str(s.getsockname()[1])
    def record():
        return json.loads((gitdir / 'workbench-setup.json').read_text())
    def leases():
        return list((root / 'state/workbench/services').glob('*/*.json'))
    def execute(command=setup, expected=0):
        call(command, '--worktree', str(tree), expected=expected)
        return record()
    def stop_listener():
        pid = root / 'pid'
        if pid.exists():
            os.kill(int(pid.read_text()), 15)
            pid.unlink()
    try:
        port()
        # External listener: attach, no lease and no Herdr calls.
        p = subprocess.Popen([sys.executable, str(listener), env['TEST_PORT']])
        for _ in range(100):
            try:
                with socket.create_connection(('127.0.0.1',int(env['TEST_PORT'])),timeout=.1): break
            except OSError: time.sleep(.02)
        r = execute()
        step = next(s for s in r['steps'] if s['name']=='services[database]')
        assert step['attach'] and step['owner']=='external' and not leases()
        assert len([s for s in r['steps'] if s['name']=='services[database]']) == 1
        assert r['services']['database']['env']['DATABASE_URL']=='postgresql://localhost/fixture'
        assert (tree/'hook-env').read_text()=='postgresql://localhost/fixture'
        call(services, '--worktree', str(tree), 'stop', 'database', expected=1)
        p.terminate(); p.wait()
        port()
        r=execute(attach_setup, 6)
        assert r['blocker']['code']=='service-unavailable' and not r['blocker']['startAttempted']
        env['TEST_NO_WORKSPACE']='1'
        missing=execute(expected=6)['blocker']
        assert missing['code']=='service-workspace-missing'
        assert 'database' in missing['remediation'] and 'python3 "$TEST_LISTENER" "$TEST_PORT"' in missing['remediation']
        del env['TEST_NO_WORKSPACE']
        env['TEST_FAIL_START']='1'
        r=execute(expected=6)
        assert r['status']=='blocked' and r['blocker']['startAttempted']
        assert r['blocker']['code']=='service-unavailable'
        print('blocked sample:',json.dumps(r))
        path=leases()[0]
        lease=json.loads(path.read_text())
        assert lease['state']=='start-failed'
        again=execute(expected=6)['blocker']
        assert not again['startAttempted']
        for item in (str(path),'fixture-owner','main-ws:t1','main-ws:p1',
                     'workbench-services --worktree '+str(main)+' status database',
                     'workbench-services --worktree '+str(main)+' stop database',
                     '--as-owner fixture-owner','workbench-services --worktree '+str(tree)+' detach'):
            assert item in again['remediation'], (item,again)
            assert item in r['blocker']['remediation'], (item,r)
        call(services,'--worktree',str(tree),'stop','database',expected=1)
        call(teardown,'--worktree',str(tree))
        assert not json.loads(path.read_text())['attached']
        env['COTAL_NAME']='other'
        call(services,'--worktree',str(tree),'stop','database',expected=1)
        call(services,'--worktree',str(tree),'--as-owner','fixture-owner','stop','database')
        env['COTAL_NAME']='fixture-owner'
        del env['TEST_FAIL_START']
        r=execute()
        assert r['status']=='ok'
        path=leases()[0]; lease=json.loads(path.read_text())
        assert lease['owner']=='fixture-owner' and lease['attached']==[str(tree)]
        assert lease['command']=='python3 "$TEST_LISTENER" "$TEST_PORT"'
        print('lease sample:',json.dumps(lease))
        calls=[json.loads(line) for line in (root/'herdr-log').read_text().splitlines()]
        assert ['tab','create','--workspace','main-ws','--cwd',str(main),'--label','services:database'] in calls
        assert ['pane','run','main-ws:p1',lease['command']] in calls
        r=execute()
        assert next(s for s in r['steps'] if s['name']=='services[database]')['attach']
        assert json.loads(path.read_text())['attached']==[str(tree)]
        live=json.loads(call(services,'--worktree',str(tree),'status'))
        assert live['database']['up'] and live['database']['paneExists'] is True
        env['TEST_PANE_ERROR']='pane not found: main-ws:p1'
        assert json.loads(call(services,'--worktree',str(tree),'status'))['database']['paneExists'] is False
        env['TEST_PANE_ERROR']='Herdr transport unavailable'
        assert json.loads(call(services,'--worktree',str(tree),'status'))['database']['paneExists'] is None
        del env['TEST_PANE_ERROR']
        fake.rename(binary/'herdr-offline')
        assert json.loads(call(services,'--worktree',str(tree),'status'))['database']['paneExists'] is None
        (binary/'herdr-offline').rename(fake)
        call(teardown,'--worktree',str(tree))
        env['TEST_TAB_ERROR']='Herdr transport unavailable'
        call(services,'--worktree',str(tree),'stop','database',expected=1)
        assert path.exists()
        env['TEST_TAB_ERROR']='tab not found: main-ws:t1'
        assert 'lease removed; recorded tab no longer exists' in call(services,'--worktree',str(tree),'stop','database')
        del env['TEST_TAB_ERROR']
        assert not leases()
        assert ['tab','close','main-ws:t1'] in [json.loads(l) for l in (root/'herdr-log').read_text().splitlines()]
        # Also exercise native TCP probe, not just command probes.
        spec=importlib.util.spec_from_file_location('services_helper',helper)
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        assert module.probe({'tcp':'127.0.0.1:'+env['TEST_PORT']},main)
        stop_listener()
        port()
        devenv=binary/'devenv'
        devenv.write_text('#!/bin/sh\n[ "$1" = up ] && [ "$2" = fixture-process ] || exit 9\nexec python3 "$TEST_LISTENER" "$TEST_PORT"\n')
        devenv.chmod(0o755)
        config=root/'services.json'
        config.write_text(json.dumps({'database': {'probe': {'tcp': '127.0.0.1:'+env['TEST_PORT']},
            'process': 'fixture-process', 'start': None, 'autostart': True, 'startTimeout': 2, 'env': {}}}))
        env['WORKBENCH_SERVICES_CONFIG']=str(config)
        result=json.loads(call(sys.executable,helper,'--worktree',str(tree),'ensure','database'))
        assert 'blocker' not in result
        assert json.loads(leases()[0].read_text())['command']=='devenv up fixture-process'
        call(teardown,'--worktree',str(tree))
        call(services,'--worktree',str(tree),'stop','database')
    finally:
        if p.poll() is None:
            p.terminate(); p.wait()
        stop_listener()
    print('shared services fixtures passed')
