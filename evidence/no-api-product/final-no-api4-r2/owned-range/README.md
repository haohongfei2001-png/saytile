# Frozen 1067f1ad owned-range native acceptance

Nine owned-range scenarios passed against real AppKit AX setters and the production coordinator/Store. The runner creates fresh isolated synthetic targets, checks exact fixture PID/nonce, and rejects key/main windows or keyboard events. Source hashes were unchanged; all three compiled binary hashes match before/after execution. All fixture processes were cleaned up.

The focus-change case verifies the real owned window first responder and its AX identifier through nonce/PID-checked IPC, reflects that responder in the pre-existing target-selection seam, and proves final production snapshot rejection with no extra setter. It does **not** certify background AX focus notifications or the production foreground resolver. No coordinator callback/invalidation is fabricated. Other original ownership, manual-edit, selected-range, refusal, restart and no-replay assertions remain strict.

`summary.json`, `probe.log`, `preflight.log` and `binary-identities.json` are the retained evidence. Historical foreground resolver UNKNOWN and application TCC boundaries remain unchanged.
