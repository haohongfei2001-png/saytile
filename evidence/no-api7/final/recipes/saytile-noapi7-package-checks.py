import sys,pathlib,hashlib,json,os,subprocess as sp
root=pathlib.Path.cwd(); out=root/'evidence/no-api7/final'; meta=json.loads((out/'package-identity.json').read_text()); app=pathlib.Path(meta['app_path']); bin=app/'Contents/MacOS/Saytile'; dmg=pathlib.Path(meta['dmg_path'])
sha=os.environ['SAYTILE_EXPECTED_REVISION']; assert meta['source_revision']==sha and sp.check_output(['git','rev-parse','HEAD'],text=True).strip()==sha
h=lambda x:hashlib.sha256(x.read_bytes()).hexdigest()
assert h(bin)==meta['binary_sha256'] and h(dmg)==meta['dmg_sha256']
shared=['--expected-source',sha,'--expected-version',meta['version'],'--expected-binary-sha256',meta['binary_sha256']]
todo={'cloud-probe-cli':['python3','research/asr/validation/fusion-quality/check-probe-isolation.py','--app',str(bin)],'connection-setup-cli':['python3','scripts/test-connection-setup.py','--app',str(app)],'install-upgrade':['python3','scripts/test-install-upgrade.py','--dmg',str(dmg),'--previous-dmg','/Users/hhf/Documents/GitHub/saytile/dist/Saytile-1.0.0-rc.1-arm64.dmg',*shared],'app-idle':['python3','scripts/test-app-idle.py','--app',str(app),'--seconds','300',*shared]}
for key in sys.argv[1:]:
 cmd=todo[key]+['--output',str(out/(key+'.json'))]
 with (out/(key+'-console.log')).open('wb') as f: cp=sp.run(cmd,stdout=f,stderr=sp.STDOUT)
 assert not cp.returncode,key
 info=json.loads((out/(key+'.json')).read_text())
 assert h(bin)==meta['binary_sha256']
 print(key,{k:info[k] for k in ['status','count','passed','wall_seconds','scope'] if k in info},flush=True)
