from pathlib import Path
import importlib.util, os, json, hashlib
root=Path('/private/tmp/saytile-natural-paragraphs')
out=Path('/private/tmp/saytile-natural-input-gap')
compiled=Path('/private/tmp/saytile-owned-range-native-jpxc4j31/production')
os.environ['SAYTILE_INPUT_SCRATCH']=str(out/'background-scratch')
os.environ['SAYTILE_INPUT_EVIDENCE_DIRECTORY']=str(out/'background-evidence')
assert (compiled/'libSaytileKit.a').exists()
spec=importlib.util.spec_from_file_location('background_input_fixture',root/'scripts/test-input-native.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
# Reuse the just-compiled exact-source library, avoiding a second identical build.
# All fixture launch, AX assertions and foreground-isolation checks remain the
# existing script's unmodified default nonactivating path.
module.package_flags=['-D','SAYTILE_PACKAGE_PROBE','-I',str(compiled),'-Xcc','-fmodule-map-file='+str(compiled/'CAudio.modulemap'),'-L',str(compiled),'-lSaytileKit','-lc++']
module.run_fixture('AXTextFixture','AXCoordinatorProbe','input-native-coordinator.log','FIXTURE_READY')
module.run_fixture('AXWebFixture','AXWebCoordinatorProbe','input-webkit-observer.log','WEB_FIXTURE_READY',True)
receipt={'status':'PASS','driver':'unchanged scripts/test-input-native.py run_fixture default nonactivating AppKit + WKWebView','linkage':'existing exact-source library from test-owned-range-native.py, no second product build','library':str(compiled/'libSaytileKit.a'),'librarySHA256':hashlib.sha256((compiled/'libSaytileKit.a').read_bytes()).hexdigest(),'coordinatorSHA256':hashlib.sha256((root/'Sources/SaytileKit/InputCoordinator.swift').read_bytes()).hexdigest(),'visibleChromeLaunched':False,'foregroundBatch':'NOT_RUN'}
(out/'background-summary.json').write_text(json.dumps(receipt,indent=2)+'\n')
