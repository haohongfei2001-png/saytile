#!/usr/bin/env python3
"""Run the unchanged NaturalParagraphTests bodies against the native SQLite library.
This is a bounded storage check, not a replacement for the full Swift Testing job.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, re, subprocess as sp
ROOT = Path(__file__).resolve().parents[3]
TEST = ROOT / 'tests/SaytileKitTests/NaturalParagraphTests.swift'
SOURCES = ['Sources/SaytileKit/TranscriptTimeline.swift', 'Sources/SaytileKit/Store.swift',
           'Sources/SaytileKit/PanelEditTransaction.swift', 'tests/SaytileKitTests/NaturalParagraphTests.swift']
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def command(args, path):
    with path.open('w') as log:
        sp.run([str(x) for x in args], cwd=ROOT, stdout=log, stderr=sp.STDOUT, check=True)
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--scratch',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True);a.scratch.mkdir(parents=True,exist_ok=True)
    initial={name:sha(ROOT/name) for name in SOURCES}
    build=['swift','build','--product','SaytileKit','--scratch-path',a.scratch,'--disable-sandbox','-Xswiftc','-enable-testing','-j','4']
    command(build,a.output/'kit-build.log')
    folder=Path(sp.run([str(x) for x in build+['--show-bin-path']],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip())
    modulemap=folder/'../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap'
    if not modulemap.exists():modulemap=folder/'CAudio.build/module.modulemap'
    source=TEST.read_text();names=re.findall(r'@Test func (\w+)\(',source)
    assert names and len(set(names))==len(names)
    runner=source.replace('import Testing\n','').replace('@Test ','')
    runner+='\n@main struct RunNaturalParagraphs {\n @MainActor static func main() async throws {\n let t=NaturalParagraphTests()\n'
    for name in names:runner+=f' try await t.{name}(); print("PASS {name}")\n'
    runner+=f' print("NATURAL_PARAGRAPHS_PASS tests={len(names)}")\n }}\n}}\n'
    path=a.output/'runner.swift';path.write_text(runner)
    exe=a.scratch/'natural-paragraph-runner'
    flags=['swiftc','-swift-version','6','-parse-as-library','-module-cache-path',a.scratch/'runner-module-cache',
           '-I',ROOT/'Sources/CSQLite','-I',folder,'-I',folder/'Modules','-Xcc','-fmodule-map-file='+str(modulemap)]
    command(flags+['-L',folder,'-lSaytileKit','-lc++',path,'-o',exe],a.output/'runner-build.log')
    command([exe],a.output/'results.log')
    result=(a.output/'results.log').read_text()
    assert len(re.findall(r'^PASS ',result,re.M))==len(names) and f'NATURAL_PARAGRAPHS_PASS tests={len(names)}' in result
    plugin=Path('/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib')
    typecheck='NOT_RUN: Testing macro plugin unavailable'
    if plugin.exists():
        command(flags+['-typecheck','-F','/Library/Developer/CommandLineTools/Library/Developer/Frameworks',
                       '-load-plugin-library',plugin,TEST],a.output/'swift-testing-typecheck.log')
        typecheck='PASS'
    assert initial=={name:sha(ROOT/name) for name in SOURCES},'Source changed during check'
    info=dict(status='PASS',timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(),
              baseline=sp.run(['git','rev-parse','HEAD'],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip(),
              source_hashes=initial,tests=len(names),passed=len(names),failed=0,test_names=names,
              framework_execution='NOT_RUN here: test bodies run as native standalone functions; full Swift Testing is separate',
              swift_testing_typecheck=typecheck,fixtures='generated SQLite and metadata only; no user archive, microphone, network API or model inference',
              runner_sha256=sha(path))
    (a.output/'receipt.json').write_text(json.dumps(info,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(info,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
