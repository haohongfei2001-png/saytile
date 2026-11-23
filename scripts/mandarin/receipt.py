"""Bind cloned-model QA, the developer-signed delivery, source and replay fixtures."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

p=argparse.ArgumentParser()
for name in ("app","dmg","probe","library","output"):p.add_argument("--"+name,type=Path,required=True)
a=p.parse_args()
def digest(path):
    with path.open("rb") as f:return hashlib.file_digest(f,"sha256").hexdigest()
def describe(path):
    return {"sha256":digest(path),"bytes":path.stat().st_size}
info=plistlib.loads((a.app/"Contents/Info.plist").read_bytes())
sha=info["SaytileSourceRevision"]
assert not info["SaytileSourceDirty"]
subprocess.run(["git","diff","--exit-code",sha,"--","Sources","native/LocalASR","packaging","Package.swift"],check=True)
root=Path("evidence/mandarin")
doc={"app_source":sha,"bundle_id":info["CFBundleIdentifier"],"release":info["SaytileReleaseVersion"],
     "platform":{k:subprocess.check_output(cmd,text=True).strip() for k,cmd in {
         "macos":["sw_vers","-productVersion"],"build":["sw_vers","-buildVersion"],"arm":["uname","-m"],
         "chip":["sysctl","-n","machdep.cpu.brand_string"],"physical_bytes":["sysctl","-n","hw.memsize"]}.items()},
     "dmg":describe(a.dmg),"app_executable":describe(a.app/"Contents/MacOS/Saytile"),
     "bundled_workers":{f.name:describe(f) for f in (a.app/"Contents/Helpers").iterdir() if f.is_file()},
     "quality_harness":{"fixture_source":describe(Path("tests/fixtures/MandarinCohort.swift")),
                        "binary":describe(a.probe),"linked_debug_library":describe(a.library)},
     "fixtures":{f.name:describe(f) for f in [root/"paired.json",root/"aishell.json",root/"panel-cohort.json"]},
     "models":{}}
for name in ["sherpa","zipformer","qwen-small"]:
    file=a.app/"Contents/Resources/LocalASR"/(name+".json")
    m=json.loads(file.read_text());doc["models"][name]={"revision":m["revision"],"repo":m["repo"],
            "manifest":describe(file),"total_bytes":sum(r["bytes"] for r in m["files"]),"license":m["license"]}
a.output.write_text(json.dumps(doc,indent=2)+"\n")
