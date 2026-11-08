#!/bin/bash
# Independent fixed-batch AVAudioConverter reference; accelerated, no VAD or wall-clock claim.
set -euo pipefail
cd "$(dirname "$0")/../../.."
[[ "$SAYTILE_FROZEN_SHA" =~ ^[0-9a-f]{40}$ && "$SAYTILE_FROZEN_TREE" =~ ^[0-9a-f]{40}$ ]]
[[ "$(git rev-parse HEAD)" == "$SAYTILE_FROZEN_SHA" && "$(git rev-parse 'HEAD^{tree}')" == "$SAYTILE_FROZEN_TREE" ]]
probe_prefix="/tmp/saytile-no-api8-${SAYTILE_FROZEN_SHA:0:12}"
probe_build="$probe_prefix-static/build"
probe_bin="$(swift build --product SaytileKit --scratch-path "$probe_build" -Xswiftc -enable-testing --show-bin-path)"
probe_map="$probe_bin/../../Intermediates.noindex/GeneratedModuleMaps/CAudio.modulemap"
if [[ ! -f "$probe_map" ]]; then probe_map="$probe_bin/CAudio.build/module.modulemap"; fi
swiftc -O -swift-version 6 -parse-as-library -I Sources/CSQLite -I "$probe_bin" -I "$probe_bin/Modules" \
  -Xcc "-fmodule-map-file=$probe_map" -L "$probe_bin" -lSaytileKit -lc++ \
  evidence/no-api-product/audio-buffer-ownership/ConverterBoundaryProbe.swift \
  -o "$probe_prefix-reference-probe"
"$probe_prefix-reference-probe" evidence/no-api-product/intermediate-d4b9dbe/local/realtime-synthetic-source.aiff "$probe_prefix-reference" 1800 \
  > evidence/no-api8/local/conversion-reference.log
python3 - <<'PY'
import hashlib,json,os,pathlib,subprocess
if not __debug__: raise SystemExit("Use normal Python execution for evidence assertions")
out=pathlib.Path('evidence/no-api8/local')
rows=json.loads((out/'conversion-reference.log').read_text());assert len(rows)==1
r=rows[0];data=pathlib.Path(r['outputPath']);source=pathlib.Path('evidence/no-api-product/audio-buffer-ownership/ConverterBoundaryProbe.swift');binary=pathlib.Path('/tmp/saytile-no-api8-'+os.environ['SAYTILE_FROZEN_SHA'][:12]+'-reference-probe')
feed=[x for x in r['statuses'] if x.startswith('feed:')]
assert feed and all(':supplied=true:' in x for x in feed), 'Reference discarded an unaccepted input batch'
assert r['inputFrames']==39690000 and r['normalFrames']+r['tailFrames']==28800000 and data.stat().st_size==57600000
report={'status':'PASS','scope':'Independent real AVAudioConverter, fixed 8192-frame batches, every input callback acceptance checked, no VAD; accelerated reference only','source_revision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'input_frames':r['inputFrames'],'output_frames':r['normalFrames']+r['tailFrames'],'tail_frames':r['tailFrames'],'feed_calls':len(feed),'all_source_batches_supplied':True,'reference_path':str(data),'reference_sha256':hashlib.sha256(data.read_bytes()).hexdigest(),'reference_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'reference_probe_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()}
(out/'conversion-reference.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
PY
