from pathlib import Path
import json,re,subprocess
here=Path.cwd()
prod=Path('/private/tmp/saytile-preview-013/native/LocalASR/.build')
release=prod/'arm64-apple-macosx/release'
jobs=json.loads((release/'description.json').read_text())['swiftCommands']
for name,src in [('Qwen3ASR','Qwen3ASR'),('SaytileModelWorker','Worker')]:
 if (here/'objects'/f'{name}.o').exists() and max(x.stat().st_mtime for x in (here/src).glob('*.swift')) < (here/'objects'/f'{name}.o').stat().st_mtime:continue
 job=jobs[f'C.{name}-arm64-apple-macosx-release.module']
 args=job['otherArguments'][:]
 for flag in ['-parseable-output','-serialize-diagnostics','-emit-objc-header','-g','-whole-module-optimization']:
  if flag in args:args.remove(flag)
 if '-emit-objc-header-path' in args:
  at=args.index('-emit-objc-header-path');del args[at:at+2]
 args[args.index('-module-cache-path')+1]='/private/tmp/saytile-qwen-fused474/ModuleCache'
 at=args.index('-num-threads');del args[at:at+2]
 args.remove('-j10')
 subprocess.run([job['executable'],'-module-name',name,'-emit-module','-emit-module-path',str(here/'objects'/f'{name}.swiftmodule'),'-c','-whole-module-optimization','-o',str(here/'objects'/f'{name}.o'),'-I',str(here/'objects'),'-I',job['importPath'],*args,*map(str,sorted((here/src).glob('*.swift')))],check=True)
link_line=next(x for x in (prod/'release.yaml').read_text().splitlines() if x.startswith('    args:') and 'SaytileModelWorker.product/Objects.LinkFileList' in x)
args=json.loads(link_line.strip()[6:]);args[args.index('-o')+1]=str(here/'SaytileModelWorker')
ix=next(i for i,x in enumerate(args) if 'Objects.LinkFileList' in x)
objects=[p for p in Path(args[ix][1:]).read_text().splitlines() if all('/'+name+'.build/' not in p for name in ['Qwen3ASR','SaytileModelWorker'])]
f=here/'objects/link';f.write_text('\n'.join(objects+[str(here/'objects/Qwen3ASR.o'),str(here/'objects/SaytileModelWorker.o')])+'\n');args[ix]='@'+str(f)
subprocess.run(args,check=True)
