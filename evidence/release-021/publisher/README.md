# 563 publisher closure: two bounded hypotheses, neither admitted

Baseline: exact `LocalLiveText` and `RecognitionUTF16` copied from product
8514fea5d45a778aae84854db9b139f7a1fbb85b. `Baseline563.swift` is a research
snapshot, not another product implementation. No production source was changed.

Reproduce: compile the three Swift files with `swiftc -O -parse-as-library`,
output `/private/tmp/saytile-closure-replay`, then run `replay.py` from this tree.
It replays 34 original receipts (30 normal, four loaded), verifies public WAV
hashes, and uses the unchanged cadence and reversal scorers. Replay time is the
raw candidate arrival time; it does NOT include native dispatch/render delay.
`replay.json.gz` preserves every accepted full hypothesis and `results.json`
every per-clip result. Final strings must be identical; preview stable UTF-16
must remain zero. Assertions enforce that no display text is spliced.

1. **FAIL, local anchored changes + corroborated new tail.** At most two short
   ordinary-Han changes, six unchanged characters on both sides, two matching
   new characters from consecutive raw candidates. No benefit on the failing
   trace: maximum useful gap remains 2.549 s at raw arrival (native baseline
   was 2.564 s). Across receipts, two short A→B→A events remain. The existing
   observation that tail-only reversals were zero does not establish that all
   earlier-word reversals were zero.
2. **FAIL, the same proposal plus a no-return lexical guard.** Prevents those
   preview reversals, but blocks subsequent full hypotheses: loaded maximum
   useful gaps become 8.948–9.914 s. This is clearly worse, not a candidate.

The critical raw trace is `pressure8/loaded-new-2`. Publication at 23.134 s
contains more spelling of an incorrect proper name but no previously unseen
reference bigram. The 23.767 s and 24.489 s hypotheses add speech while also
changing earlier words. The latter has only one observation of one changed
word. Publishing it earlier by a timer would remove evidence requirements.
Freezing the old word while attaching the new tail would manufacture a string
never produced by the model. Neither is an acceptable fix. The baseline next
publishes at 25.108 s. This measured failure remains open.

These are the two permitted hypotheses for this direction, not a parameter
search. Neither enters the installable product. A final signed closure build
will be compared with 563 in three paired native runs; unchanged publisher
code cannot be represented as an algorithm improvement or CPU reduction.
