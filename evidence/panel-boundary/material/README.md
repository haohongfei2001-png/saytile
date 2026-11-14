# Native frosted-material comparison

The captured product UI source is `9e00287f24bd959d609cb6ceafa0164b90fae6fc`; the existing 0.13 (476) desktop reference is `0fbca1d892bbc8aa550c4439b8cfcb045af825ae`.

## Scope

PASS: four actual WindowServer-composited native panel captures, border on/off × desktop/fullscreen material. Each PNG is 688 × 380 pixels (344 × 190 logical points). Only two self-owned nonactivating fixture windows were captured: the panel and a synthetic striped background. The same synthetic editable text, editor identity, font size, control geometry and card rectangle are retained. No installed Saytile, microphone, private windows or production data were used. Neither fixture became the key window.

The fullscreen material environment value was injected. Actual system fullscreen detection, external-window movement/restoration, and accessibility permission behavior are NOT_RUN **by this material probe**; their separate native acceptance receipts must be consulted. Geometry checks and image comparison do not represent the user's final aesthetic approval.

## Observed appearance

The ordinary material keeps the existing light translucent glass. Its border-off capture is byte-identical to 476. The border-on pair has tiny compositor variation (mean absolute RGB difference 0.004241 on a 0–255 scale, maximum 1.719666), rather than a claim of exact pixel equality.

The fullscreen variant visibly increases the white frost and reduces the background stripes without moving text or buttons. In the same empty pixel patch `[64,180,624,260]`, brightness standard deviation changes from 14.630 to 0.356 with the border and 26.038 to 1.532 without it. This describes this synthetic background only, not a general contrast/accessibility score.

All four variants retain a 14.04 pt font, 54 × 26 pt voice control, 30 × 26 pt copy control, and the same 322.831 × 168.831 pt inner card rectangle. Refer to `candidate/glass-receipt.json` for the complete geometry.

## Reproduce

From the repository root, with screen capture permission already available (the fixture refuses rather than requests it):

```sh
python3 scripts/test-adaptive-panel.py --source 9e00287 --output /tmp/saytile-glass-current --glass-only --expect-pass
python3 scripts/test-adaptive-panel.py --source 0fbca1d892bbc8aa550c4439b8cfcb045af825ae --output /tmp/saytile-glass-reference --glass-only --expect-pass
swift evidence/panel-boundary/material/compare.swift /tmp/saytile-glass-reference /tmp/saytile-glass-current
```

The baseline raw receipt is preserved in full for provenance, but **only its desktop PNGs are used as the baseline**. The 476 source has no fullscreen material variant; an injected fullscreen flag has no effect there. The candidate fixture uses the source-bound repository component code, not static imagery or an HTML reconstruction.

`comparison.json` binds the candidate PNGs and four component sources to SHA-256. `component-readback.json` verifies those components stayed unchanged while the manager-only corrections continued. `SHA256SUMS.json` covers this evidence directory except itself. The retained screenshot set is limited to the panel bounds.
