# Saytile architecture research status

Updated: 2026-11-07. This file describes the research/architecture revision branch, not production main.

## Branch identity

- PR #4 remains open and unmerged; its current head at review time: `8f2d71b73c8ae1aa421719201a263de20d98fc7f`.
- This documentation revision is PR #5, stacked on PR #4's branch.
- PR #5 head: `2ef09940357b3fe8d4151b73687120d90fc34d38`.
- Production main and the installed V1 RC1 were not changed.

## Completed in this revision

- Competitor architecture research for Aqua Voice, Wispr Flow, Superwhisper, Willow, VoiceInk, Typeless and Apple SpeechAnalyzer.
- Competitive advantage and gap assessment.
- Final adaptive hybrid architecture and data-flow diagram.
- V1/V2/V3 development roadmap with priorities, dependencies, validation and acceptance gates.
- Updated ASR decision, implementation, BYOK acceptance, product roadmap and revision history.

## Not completed

- No source-code implementation of the new unified Apple/cloud Candidate ingress.
- No live Soniox v6 or other paid provider calls.
- No new cloud accuracy/latency measurements.
- No target-Mac local model performance or thermal benchmark.
- No full 24-hour soak or production offline recovery acceptance.

## Immediate next engineering sequence

1. Implement the unified Candidate ingress for Apple SpeechAnalyzer and cloud providers without changing capture/PCMJournal durability.
2. Add policy trace and configurable model plan; keep all new challengers off until explicitly enabled.
3. Use existing audio corpus for a small authorized 24-sample paired evaluation: Apple, Soniox v6, Qwen+Assembly, Meta challenger.
4. Admit models based on net error reduction, critical-term error reduction, p50/p95 stage latency, thermal/resource cost and reliability.
5. Implement minimal V1 context (frontmost app identity, explicit selection, user terms); no automatic screenshot or clipboard-wide collection.
6. Finish raw/formatted/user-edited transcript separation and Backtrack only for un-dispatched text.
7. Complete long-run, network-loss, recovery, permissions, focus-change and input-ledger release gates.

No paid model calls, private audio upload, production merge, RC1 replacement or production database mutation was performed in this research revision.
