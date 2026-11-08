import datetime, hashlib, json, pathlib, queue, subprocess, threading, uuid
root=pathlib.Path(__file__).resolve().parent
nonce=uuid.uuid4().hex
fixture=subprocess.Popen([str(root/'fixture'),nonce],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
q=queue.Queue(); result={'started':datetime.datetime.now(datetime.timezone.utc).isoformat(),'fixture_pid':fixture.pid,'nonce':nonce,'fixture_events':[]}
threading.Thread(target=lambda:[q.put(line.strip()) for line in fixture.stdout],daemon=True).start()
def receive(event, timeout=5):
    while True:
        line=q.get(timeout=timeout)
        msg=json.loads(line); assert msg['pid']==fixture.pid and msg['nonce']==nonce
        result['fixture_events'].append(msg)
        assert not msg['key'] and not msg['main'] and not msg['canKey'] and not msg['canMain'] and msg['alpha']==0
        assert not msg['activated'] and msg['keyboardEvents']==0 and msg['foregroundUnchanged']
        if msg['event']==event: return msg
try:
    ready=receive('ready')
    p=subprocess.run([str(root/'probe'),str(fixture.pid),nonce],capture_output=True,text=True,timeout=12)
    result['probe_exit']=p.returncode;result['probe_stdout']=p.stdout.strip();result['probe_stderr']=p.stderr.strip()
    if p.returncode==0:
        action=receive('realMenuItemAction');assert action['actions']==1
        result['outcome']='OWNED_AX_SHOW_MENU_AND_AXPRESS_VERIFIED'
    elif p.returncode==5:
        fixture.stdin.write('fallback\n');fixture.stdin.flush()
        action=receive('directAttachedNSMenu');assert action['actions']==1
        result['outcome']='AX_CONTEXT_UNVERIFIED_DIRECT_ATTACHED_NSMENU_ACTION_VERIFIED'
    else: raise RuntimeError(f'probe failed {p.returncode}')
    fixture.stdin.write('finish\n');fixture.stdin.flush();end=receive('finished')
    fixture.wait(timeout=4)
    assert fixture.returncode==0 and end['actions']==1
except Exception as exc:
    result['outcome']='FAIL';result['error']=str(exc)
finally:
    if fixture.poll() is None:
        fixture.terminate()
        try:fixture.wait(timeout=2)
        except subprocess.TimeoutExpired: fixture.kill();fixture.wait()
    result['fixture_exit']=fixture.returncode;result['fixture_stderr']=fixture.stderr.read()
    result['finished']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    result['identities']={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ['Fixture.swift','Probe.swift','fixture','probe','run.py']}
    (root/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False,indent=2));raise SystemExit(result['outcome']=='FAIL')
