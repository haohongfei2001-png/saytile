from pathlib import Path
import os,runpy,hashlib,json,subprocess,sys
root=Path('/private/tmp/saytile-release-101')
mode=sys.argv[1]; assert mode in ['stable','audio']
out=root/'evidence/release-101'/('qwen-input-'+mode);out.mkdir(exist_ok=True)
os.environ['SAYTILE_INPUT_SCRATCH']='/private/tmp/saytile-release101-input-final'
os.environ['SAYTILE_INPUT_EVIDENCE_DIRECTORY']=str(out)
p=runpy.run_path(str(root/'scripts/test-input-native.py'))
product=Path('/private/tmp/saytile-release101-storage/build/out/Products/Debug')
module=product/'../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap'
assert module.exists()
p['production_flags'].__globals__['package_flags']=['-D','SAYTILE_PACKAGE_PROBE','-I',str(product),'-I',str(product/'Modules'),'-Xcc','-fmodule-map-file='+str(module),'-L',str(product),'-lSaytileKit','-lc++']
binding=json.loads((root/'evidence/release-101/storage/source-equivalence-public.json').read_text())
if mode=='stable':
 source=root/'evidence/release-101/regression-final/paired16/qwen-current/continuous-public-5/visible-raw.json'
 assert json.loads(source.read_text())['sha']=='73ad857442964437929819ba9965f6bcfdcefd27'
 os.environ['SAYTILE_QWEN_STABLE_REPLAY']=str(source)
else:
 source=Path('/private/tmp/saytile-beta-021-20261123/.build/mandarin/wav/continuous-public-5.wav')
 assert hashlib.sha256(source.read_bytes()).hexdigest()=='5e7b5564803cec7cb90282b0427e99cd345472b758464060bf1f2ae5ba013c04'
 os.environ['SAYTILE_QWEN_NATIVE_AUDIO']=str(source)
 os.environ['SAYTILE_QWEN_NATIVE_WEIGHTS']='/private/tmp/saytile-beta-021-20261123/.build/local-asr/weights'
 os.environ['SAYTILE_QWEN_NATIVE_HELPERS']='/private/tmp/saytile-release101-public/Saytile.app/Contents/Helpers'
status='FAIL'
try:
 p['run_fixture']('AXTextFixture','AXCoordinatorProbe','input-'+mode+'.log','FIXTURE_READY')
 status='PASS'
finally:
 (out/'binding.json').write_text(json.dumps({'status':status,'product_source':'73ad857442964437929819ba9965f6bcfdcefd27','mode':mode,'input_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'fixture_sha256':hashlib.sha256((root/'tests/fixtures/AXCoordinatorProbe.swift').read_bytes()).hexdigest(),'kit_library_sha256':hashlib.sha256((product/'libSaytileKit.a').read_bytes()).hexdigest(),'source_equivalence':binding,'foreground_resolver':'NOT_RUN: owned background target injected; CI tests real resolver separately','physical_microphone':'NOT_RUN','paid_api':'NOT_CALLED'},indent=2)+'\n')
