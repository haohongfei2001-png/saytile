from pathlib import Path
import hashlib,json,plistlib,subprocess as sp,sys,tempfile,time
work=Path.cwd(); old=Path('/private/tmp/saytile-local-quality-20261114')
wav=old/'.build/mandarin/wav';weights=old/'.build/local-asr/weights'; temp=Path(__file__).parent
app=Path(sys.argv[1]);out=temp/sys.argv[2]
out.mkdir(exist_ok=True)
info=plistlib.loads((app/'Contents/Info.plist').read_bytes());sha=info['SaytileSourceRevision']; source=work/'.build/mandarin/bench'/('bin-shipping-'+sha[:8]); receipt=json.loads((source/'identity.json').read_text()); assert sha==receipt['source']
sp.run(['codesign','--verify','--strict','--deep',app],check=True)
receipt['sha256'].update(app=hashlib.sha256((app/'Contents/MacOS/Saytile').read_bytes()).hexdigest(),worker=hashlib.sha256((app/'Contents/Helpers/SaytileModelWorker').read_bytes()).hexdigest()); receipt.update(version=info['CFBundleShortVersionString'],build=info['CFBundleVersion'],bundle=info['CFBundleIdentifier']);(out/'bench-identity.json').write_text(json.dumps(receipt,indent=2)+'\n')
(out/'runs').mkdir(exist_ok=True)
bench=old/'.build/mandarin/bench'
for label in ('paired','aishell'):
  references=json.loads((work/'evidence/mandarin'/(label+'.json')).read_text()); data=[]
  for path in sorted(bench.glob(label+'-???.json')):
    if (out/'stop-after-shard').is_file():raise SystemExit('final 476 cohort stopped after current shard')
    shard=json.loads(path.read_text()); assert references[len(data):len(data)+len(shard)]==shard
    part=(out/'runs'/path.stem).with_suffix('.part')
    existing=part.read_text().splitlines() if part.is_file() else []
    if len(existing)==len(shard) and [json.loads(row)['id'] for row in existing]==[r['id'] for r in shard]:
      assert any(json.loads(row)['text'] for row in existing), 'All shard recordings empty; stop instead of reusing failed results'
      assert all(json.loads(row)['providers'] == ['qwen-small'] for row in existing), 'Unexpected reused runtime provider'
      data.extend(existing); print(time.strftime('%X'),path.name,'valid complete rows from this same build',flush=True);continue
    with (out/'runs'/(path.stem+'.log')).open('w') as log:
      sp.run([source/'Cohort','qwen-small','product',path,wav,weights,app/'Contents/Helpers',part],cwd=app/'Contents/Resources',stdout=log,stderr=sp.STDOUT,check=True)
    rows=part.read_text().splitlines(); assert [json.loads(row)['id'] for row in rows]==[r['id'] for r in shard]
    assert any(json.loads(row)['text'] for row in rows), 'All shard recordings empty; stop for diagnosis'
    assert all(json.loads(row)['providers'] == ['qwen-small'] for row in rows), 'Unexpected runtime provider'
    data.extend(rows);print(time.strftime('%X'),path.name,flush=True)
  assert len(data)==len(references)
  (out/'runs'/(label+'-qwen-small-product.jsonl')).write_text('\n'.join(data)+'\n')
