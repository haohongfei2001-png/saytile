#!/bin/bash
set -euo pipefail
repo=/private/tmp/saytile-asr-response
scratch=/private/tmp/saytile-asr-audit-tests/out
python3 - "$repo" <<'PY'
from pathlib import Path
import sys,hashlib,json,subprocess
repo=Path(sys.argv[1]); source=(repo/'Sources/SaytileKit/AudioJournal.swift').read_text()
segmenter=source[source.index('final class VoiceSegmenter {'):]
error=source[source.index('public enum AudioFailure:'):source.index('/// Independent PCM16')]
driver=Path('/private/tmp/saytile-vad-corpus-driver.swift').read_text()
combined='import Foundation\nimport CAudio\n'+error+segmenter+'\n'+driver
Path('/private/tmp/saytile-vad-corpus-compare.swift').write_text(combined)
receipt=dict(sourceSHA=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),
 audioJournalSHA256=hashlib.sha256(source.encode()).hexdigest(),
 extractedVoiceSegmenterSHA256=hashlib.sha256(segmenter.encode()).hexdigest(),
 driverSHA256=hashlib.sha256(driver.encode()).hexdigest(),
 sourceCombinedSHA256=hashlib.sha256(combined.encode()).hexdigest())
Path('/private/tmp/saytile-vad-corpus-build.json').write_text(json.dumps(receipt,indent=2)+'\n')
PY
swiftc -O -module-cache-path /private/tmp/saytile-asr-audit-module-cache \
 -Xcc -fmodule-map-file="$scratch/Intermediates.noindex/Saytile.build/Debug/CAudio-t.build/CAudio.modulemap" \
 -I "$repo/Sources/CAudio/include" /private/tmp/saytile-vad-corpus-compare.swift \
 "$scratch/Products/Debug/CAudio.o" -lc++ -framework CoreAudio -framework AudioToolbox \
 -o /private/tmp/saytile-vad-corpus-compare
