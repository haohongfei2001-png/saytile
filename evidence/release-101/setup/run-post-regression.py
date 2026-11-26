from pathlib import Path
import json,time,subprocess,runpy,traceback
root=Path('/private/tmp/saytile-release-101'); evidence=root/'evidence/release-101'
progress=evidence/'regression-final/progress.json'
start=time.monotonic()
while True:
    events=json.loads(progress.read_text())
    if any(e.get('phase')=='queue' and e.get('status')=='COMPLETE' for e in events): break
    if time.monotonic()-start>10800: raise TimeoutError('Original sequential queue did not finish')
    time.sleep(5)
out=evidence/'startup-followup';out.mkdir(exist_ok=False)
manifest=Path('/private/tmp/saytile-experience-023/evidence/experience-023/setup/panel16.json')
sample='ascend-mixed-7c8bdcb41bb98a40'
run=runpy.run_path(str(root/'scripts/mandarin/measure-preview-cost.py'))['public_run']
results=[]
for pair in range(3):
    arms=[('baseline',Path('/private/tmp/saytile-release100-final/Saytile.app')),('candidate',Path('/private/tmp/saytile-release101-public/Saytile.app'))]
    if pair%2:arms.reverse()
    for name,app in arms:
        target=out/f'pair-{pair+1}'/name
        item=dict(pair=pair+1,arm=name,sample=sample,status='FAIL')
        try:
            run(app,manifest,sample,Path('/private/tmp/saytile-beta-021-20261123/.build/local-asr/weights'),Path('/private/tmp/saytile-beta-021-20261123/.build/mandarin/wav'),target)
            item['status']='PASS'
        except Exception:
            target.mkdir(parents=True,exist_ok=True)
            (target/'failure.txt').write_text(traceback.format_exc())
        results.append(item)
        (out/'progress.json').write_text(json.dumps(results,indent=2)+'\n')
        print(json.dumps(item),flush=True)
with (evidence/'qwen-input-audio-run.log').open('w') as log:
    p=subprocess.run(['python3','/private/tmp/saytile-release101-qwen-input.py','audio'],cwd=root,stdout=log,stderr=subprocess.STDOUT)
results.append(dict(phase='real-qwen-to-owned-AX',status='PASS' if p.returncode==0 else 'FAIL',exit=p.returncode))
(evidence/'post-regression.json').write_text(json.dumps(results,indent=2)+'\n')
print('POST_REGRESSION_COMPLETE',flush=True)
