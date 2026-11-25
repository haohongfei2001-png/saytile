#!/bin/bash
# Exact release library + immutable Hugging Face revision. No ASR or private cache.
set -euo pipefail
if [[ $# != 5 ]]; then
  echo 'usage: test-model-download-resume.sh SOURCE_CHECKOUT RELEASE_LIBRARY_DIR RESEARCH_WEIGHTS OUTPUT_DIR SOURCE_SHA' >&2
  exit 64
fi
SAYTILE_RESUME_CHECKOUT="$1"
SAYTILE_RESUME_LIB="$2"
SAYTILE_RESUME_WEIGHTS="$3"
SAYTILE_RESUME_OUTPUT="$4"
SAYTILE_RESUME_SHA="$5"
SAYTILE_RESUME_TOOLS="$(cd "$(dirname "$0")/.." && pwd)"
[[ ! -e "$SAYTILE_RESUME_OUTPUT" ]] || { echo 'Use a new evidence directory' >&2; exit 64; }
mkdir -p "$SAYTILE_RESUME_OUTPUT"
SAYTILE_RESUME_BIN="$(mktemp -d /private/tmp/saytile-model-resume-bin.XXXXXX)"
SAYTILE_RESUME_MODULE_CACHE="${SAYTILE_RESUME_MODULE_CACHE:-$SAYTILE_RESUME_BIN/module-cache}"
SAYTILE_RESUME_ROOT="/private/tmp/saytile-model-resume-$(uuidgen)"
ditto "$SAYTILE_RESUME_LIB/Saytile_SaytileKit.bundle" "$SAYTILE_RESUME_BIN/Saytile_SaytileKit.bundle"
python3 - "$SAYTILE_RESUME_CHECKOUT" "$SAYTILE_RESUME_LIB" "$SAYTILE_RESUME_OUTPUT" "$SAYTILE_RESUME_SHA" "$SAYTILE_RESUME_TOOLS" <<'PY'
from pathlib import Path
import hashlib,json,subprocess,sys
source,lib,out,sha,tools=map(Path,sys.argv[1:])
sha=str(sha)
files=['Sources/SaytileKit/LocalModelLibrary.swift','Sources/SaytileKit/Resources/LocalASR/qwen-small.json']
values={}
for name in files:
    current=(source/name).read_bytes()
    frozen=subprocess.check_output(['git','-C',str(source),'show',sha+':'+name])
    assert current==frozen, 'frozen source mismatch: '+name
    values[name]=hashlib.sha256(current).hexdigest()
manifest=(lib/'Saytile_SaytileKit.bundle/Contents/Resources/LocalASR/qwen-small.json')
if not manifest.exists(): manifest=lib/'Saytile_SaytileKit.bundle/LocalASR/qwen-small.json'
assert manifest.read_bytes()==(source/files[1]).read_bytes()
values['linkedReleaseLibrary']=hashlib.sha256((lib/'libSaytileKit.a').read_bytes()).hexdigest()
values['probe']=hashlib.sha256((tools/'tests/fixtures/LocalModelDownloadResumeProbe.swift').read_bytes()).hexdigest()
(out/'source.json').write_text(json.dumps({'sourceRevision':sha,'sha256':values,'scope':'Real URLSession HTTPS, shipped LocalModelLibrary; APFS clone of authorized research weights, not an installed cache; no ASR loaded.'},indent=2)+'\n')
PY
nice -n 20 swiftc -swift-version 6 -parse-as-library -module-cache-path "$SAYTILE_RESUME_MODULE_CACHE" \
  -I "$SAYTILE_RESUME_LIB" -I "$SAYTILE_RESUME_CHECKOUT/Sources/CSQLite" \
  -Xcc "-fmodule-map-file=$SAYTILE_RESUME_LIB/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap" \
  -L "$SAYTILE_RESUME_LIB" -lSaytileKit -lc++ \
  "$SAYTILE_RESUME_TOOLS/tests/fixtures/LocalModelDownloadResumeProbe.swift" -o "$SAYTILE_RESUME_BIN/probe" \
  > "$SAYTILE_RESUME_OUTPUT/compile.log" 2>&1
printf '%s\n' "$SAYTILE_RESUME_ROOT" > "$SAYTILE_RESUME_OUTPUT/isolated-root.txt"
nice -n 20 "$SAYTILE_RESUME_BIN/probe" "$SAYTILE_RESUME_WEIGHTS" "$SAYTILE_RESUME_ROOT" \
  "$SAYTILE_RESUME_OUTPUT/receipt.json" "$SAYTILE_RESUME_SHA" 2>&1 | tee "$SAYTILE_RESUME_OUTPUT/run.log"
