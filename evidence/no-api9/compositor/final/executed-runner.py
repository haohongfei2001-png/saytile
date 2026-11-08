"""Compile a fixed Saytile presentation and measure two synthetic owned windows only."""
import argparse, hashlib, json, os, shutil, subprocess, time
from pathlib import Path

p=argparse.ArgumentParser()
for arg in ("repo","revision","library-revision","library-scratch","output"):
    p.add_argument("--"+arg,required=True)
variant = p.add_mutually_exclusive_group()
variant.add_argument("--disposable-material-opacity", choices=("0.35","0.55"))
variant.add_argument("--use-working-style", action="store_true", help="Test the actual uncommitted presentation file; other runtime inputs must match the supplied commit.")
a=p.parse_args()
os.chdir(a.repo);out=Path(a.output).resolve();out.mkdir(parents=True,exist_ok=False)
def git(*args):return subprocess.check_output(["git",*args])
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save(name,value):(out/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n")
head=git("rev-parse",a.revision+"^{commit}").decode().strip()
baseline=git("rev-parse",a.library_revision+"^{commit}").decode().strip()
assert head==a.revision and baseline==a.library_revision
paths=["Sources/SaytileKit","Sources/CAudio","Sources/CSQLite","Package.swift"]
assert not git("diff","--name-only",baseline,head,"--",*paths)
probe_original=Path(__file__).with_name("OwnedGlassProbe.swift")
probe=out/"OwnedGlassProbe.swift";shutil.copyfile(probe_original,probe)
src=out/"sources";src.mkdir();files=[]
for name in ["AppModel","Views","CompactTranscriptView","ReferencePanelStyle","VoiceCaptureGlyph","Theme","RecognitionSettingsView","ConnectionSetupView","VoiceEntryView"]:
    rel="Sources/SaytileApp/"+name+".swift"
    content=git("show",head+":"+rel)
    if name=="ReferencePanelStyle" and a.disposable_material_opacity:
        before=b"            ReferenceGlassBackdrop()\n"
        assert content.count(before)==1
        content=content.replace(before,before+("                .opacity(reduceTransparency ? 1 : "+a.disposable_material_opacity+")\n").encode())
    elif name=="ReferencePanelStyle" and a.use_working_style:
        assert git("diff","HEAD","--name-only","--","Sources").decode().splitlines()==[rel]
        content=Path(rel).read_bytes()
    path=src/(name+".swift");path.write_bytes(content);files.append(path)
scratch=Path(a.library_scratch).resolve()/"out";debug=scratch/"Products/Debug";lib=debug/"libSaytileKit.a"
binary=out/"owned-glass-probe"
cmd=["swiftc","-swift-version","6","-parse-as-library","-module-cache-path",str(Path(__file__).with_name("cache")),
     "-I",str(debug),"-I",str(debug/"Modules"),"-I","Sources/CSQLite","-Xcc","-fmodule-map-file="+str(scratch/"Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"),
     "-L",str(debug),"-lSaytileKit","-lc++",*map(str,files),str(probe),"-o",str(binary)]
with (out/"compile.log").open("wb") as log:compiled=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
receipt={"source_revision":head,"source_tree":git("rev-parse",head+"^{tree}").decode().strip(),"library_source_revision":baseline,
    "library_inputs_unchanged":paths,"static_library_sha256":sha(lib),"production_source_sha256":{x.name:sha(x) for x in files},
    "diagnostic_sha256":sha(probe),"runner_sha256":sha(Path(__file__)),"compile_exit":compiled.returncode,
    "presentation_scope":"disposable single-factor experiment" if a.disposable_material_opacity else ("actual staged product source" if a.use_working_style else "exact committed product source"),
    "disposable_material_opacity":a.disposable_material_opacity,
    "committed_style_sha256":hashlib.sha256(git("show",head+":Sources/SaytileApp/ReferencePanelStyle.swift")).hexdigest(),
    "working_style_selected":a.use_working_style}
save("source-identity.json",receipt)
if compiled.returncode:raise SystemExit(compiled.returncode)
before=sha(binary);started=time.time()
with (out/"run.log").open("wb") as log:
    try:
        proc=subprocess.run([binary,out/"measurements.json"],stdout=log,stderr=subprocess.STDOUT,timeout=18)
        code=proc.returncode;cut=False
    except subprocess.TimeoutExpired:
        code=None;cut=True
execution={"source_revision":head,"probe_sha256_before":before,"probe_sha256_after":sha(binary),"exit":code,"owned_process_timeout":cut,"seconds":time.time()-started}
save("execution.json",execution)
if code!=0 or not (out/"measurements.json").is_file():raise SystemExit(code if code is not None else 124)
result=json.loads((out/"measurements.json").read_bytes())
assert result["all_windows_confirmed_owned"] and result["window_count"]==2 and result["capture_state_stayed_paused"]
assert result["foreground_continuity"] and not result["probe_became_active"] and result["foreground_activation_notifications"]==0
modes=list(dict.fromkeys(m["mode"] for m in result["measurements"]))
summary={}
for mode in modes:
    rows=[m for m in result["measurements"] if m["mode"]==mode]
    assert [r["synthetic_backdrop"] for r in rows]==["cool","warm","cool"]
    def diff(plane):
        return [round(rows[1][plane]["mean_srgb8"][i]-rows[0][plane]["mean_srgb8"][i],3) for i in range(3)]
    summary[mode]={"exposed_warm_minus_cool_srgb8":diff("exposed_backdrop"),
        "interior_warm_minus_cool_srgb8":diff("glass_interior"),
        "interior_stripe_contrast_cool":round(rows[0]["glass_interior"]["stripe_contrast"],3),
        "exposed_stripe_contrast_cool":round(rows[0]["exposed_backdrop"]["stripe_contrast"],3),
        "cool_mean_stable_on_return":rows[0]["glass_interior"]["mean_srgb8"]==rows[2]["glass_interior"]["mean_srgb8"]}
save("summary.json",summary)
print(json.dumps(summary,indent=2))
