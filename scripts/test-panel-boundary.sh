#!/bin/bash
set -euo pipefail
# Only disposable fixture processes are targeted. No TCC prompts or user app activation.
root=$(cd "$(dirname "$0")/.." && pwd)
products=${SAYTILE_PANEL_PRODUCTS:?Set SAYTILE_PANEL_PRODUCTS to the verified build Products/Debug directory}
run=${SAYTILE_PANEL_EVIDENCE:-$(mktemp -d /private/tmp/saytile-panel-boundary.XXXXXX)}
mkdir -p "$run/target" "$run/other" "$run/module-cache"
# Clang PCM paths must be canonical if the caller reuses a cache symlink.
module_cache="$(cd "$run/module-cache" && pwd -P)"
case "$run" in /private/tmp/*|/tmp/*) ;; *) echo 'Evidence directory must be under temporary storage.' >&2; exit 64;; esac
python3 - "$root" "$run" "$products" <<'PYSOURCE'
import hashlib,json,pathlib,shutil,subprocess,sys
root,run,products=map(pathlib.Path,sys.argv[1:]); dst=run/'source'; dst.mkdir(exist_ok=True)
paths=['tests/fixtures/PanelBoundaryTarget.swift','tests/fixtures/PanelBoundaryProbe.swift','Sources/SaytileApp/PanelWindowAccess.swift','Sources/SaytileApp/PanelCoexistenceController.swift','Sources/SaytileApp/PanelWindowEvents.swift','Sources/SaytileApp/VoicePanel.swift']
records={}
for relative in paths:
 src=root/relative; data=src.read_bytes(); (dst/src.name).write_bytes(data); records[relative]=hashlib.sha256(data).hexdigest()
record={'source_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'source_files':records,'linked_libraries':{name:hashlib.sha256((products/name).read_bytes()).hexdigest() for name in ['libSaytileKit.a','libSaytileVoiceUI.a']},'source_note':'Exact copies compiled below; concurrent working-tree changes cannot alter this probe.'}
(run/'source-binding.json').write_text(json.dumps(record,indent=2)+'\n')
PYSOURCE
xcrun swiftc -swift-version 6 -module-cache-path "$module_cache" -parse-as-library "$run/source/PanelBoundaryTarget.swift" -o "$run/PanelBoundaryTarget"
modulemap="$products/../../Intermediates.noindex/Saytile.build/Debug/CAudio-t.build/CAudio.modulemap"
if [[ ! -f "$modulemap" ]]; then modulemap="$products/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"; fi
if [[ ! -f "$modulemap" ]]; then modulemap="$products/CAudio.build/module.modulemap"; fi
[[ -f "$modulemap" ]] || { echo 'CAudio module map missing' >&2; exit 1; }
xcrun swiftc -swift-version 6 -module-cache-path "$module_cache" -parse-as-library -I "$products" -I "$products/Modules" -I "$root/Sources/CSQLite" -Xcc "-fmodule-map-file=$modulemap" \
 "$run/source/PanelBoundaryProbe.swift" "$run/source/PanelWindowAccess.swift" \
 "$run/source/PanelCoexistenceController.swift" "$run/source/PanelWindowEvents.swift" \
 "$run/source/VoicePanel.swift" "$products/libSaytileKit.a" "$products/libSaytileVoiceUI.a" \
 -lsqlite3 -lc++ -o "$run/PanelBoundaryProbe"
codesign --force --sign - "$run/PanelBoundaryTarget" "$run/PanelBoundaryProbe" >"$run/sign.log" 2>&1
if ! "$run/PanelBoundaryProbe" --permission >"$run/permission.log" 2>&1; then
 python3 - "$run" <<'PY'
import json,sys,pathlib
p=pathlib.Path(sys.argv[1]); (p/'report.json').write_text(json.dumps({'status':'BLOCKED','reason':'Accessibility not granted to this exact probe identity; no TCC change or prompt attempted','tests':[],'user_windows_written':0},indent=2)+'\n')
PY
 cat "$run/permission.log"; exit 77
fi
python3 - "$run" <<'PYAPP'
import pathlib,plistlib,shutil,sys
p=pathlib.Path(sys.argv[1])
for name,identity in [('Target','target'),('Other','other')]:
 app=p/f'{name}.app'; mac=app/'Contents/MacOS'; mac.mkdir(parents=True,exist_ok=True)
 shutil.copy2(p/'PanelBoundaryTarget',mac/'PanelBoundaryTarget')
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'PanelBoundaryTarget','CFBundleIdentifier':f'app.saytile.lab.boundary.{identity}','CFBundleName':f'Saytile {name} Fixture','CFBundlePackageType':'APPL','LSUIElement':False}))
PYAPP
codesign --force --sign - "$run/Target.app" "$run/Other.app" >>"$run/sign.log" 2>&1
"$run/PanelBoundaryProbe" --capture-frontmost "$run/frontmost.json"
cleanup() {
 python3 - "$run" <<'PYCLEAN'
import ctypes,json,os,pathlib,signal,sys
p=pathlib.Path(sys.argv[1]); lib=ctypes.CDLL('/usr/lib/libproc.dylib')
for folder,app in [('target','Target'),('other','Other')]:
 try:
  pid=int(json.loads((p/folder/'ready.json').read_text())['pid']); buf=ctypes.create_string_buffer(4096)
  if lib.proc_pidpath(pid,buf,len(buf))>0 and pathlib.Path(buf.value.decode()).resolve()==(p/f'{app}.app/Contents/MacOS/PanelBoundaryTarget').resolve(): os.kill(pid,signal.SIGTERM)
 except (OSError,KeyError,ValueError): pass
PYCLEAN
 "$run/PanelBoundaryProbe" --restore-frontmost "$run/frontmost.json" || true
}
trap cleanup EXIT
open -n -g "$run/Other.app" --args "$run/other"
open -n "$run/Target.app" --args "$run/target"
python3 - "$run" <<'PY'
import pathlib,sys,time
p=pathlib.Path(sys.argv[1]); end=time.monotonic()+10
while time.monotonic()<end:
 if (p/'target/ready.json').exists() and (p/'other/ready.json').exists(): break
 time.sleep(.05)
else: raise SystemExit('Fixture ready timeout')
PY
"$run/PanelBoundaryProbe" "$run/target" "$run/other" "$run/report.json" | tee "$run/probe.log"
