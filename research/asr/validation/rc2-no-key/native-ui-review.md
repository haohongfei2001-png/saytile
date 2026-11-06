# Candidate.2 native UI review

The final DMG-extracted App, source `7320228955cec7bb4d24ff19700f37d1ef0ddbc3`, binary `d109e06018ae231f2a1a55c82d38505937298172c929fc7df07d86b374e382f9`, was launched with an independent synthetic database using the existing native review mode. It attached production SwiftUI to transparent nonactivating AppKit windows; this is not the HTML prototype and not an interactive real-user speech session.

15 captures / 6 control groups passed, including 16 actual AXPress actions, 2 AXSetValue actions and 2 native field-editor commits. The candidate never activated; this run recorded zero outside foreground transitions. The connection Finish button correctly refused unfinished setup; no keys were read and no provider called. Exact captures and hashes are in ui-final-manifest.json; action evidence is ui-final.log.

Root visually inspected the actual panel review state, five-service settings and compact archive detail images below. Text remained readable, service sections and save state aligned, archived drafts/versions remained visible, and compact detail used the existing scrollable layout. No new concrete visual defect was identified in these views. This does not prove live streaming text animation, actual model latency, physical display/Spaces transitions or subjective final product approval.

- [Input panel with synthetic review state](images/panel-ai-review.png)
- [Five-service settings](images/ai-services.png)
- [Compact archive detail](images/archive-detail-compact.png)

Reproduce: `python3 scripts/test-native-ui.py --app dist/Saytile.app --output dist/rc2-no-key-ui --controls`. Use the intended bundle identified above; controls require already granted AX access and do not request it.
