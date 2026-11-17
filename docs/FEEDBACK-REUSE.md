# Feedback core reuse

0.20（533）整合状态见[本轮交付](delivery/saytile-next-release/RELEASE.md)。当前个人内测已安装可离线保存的反馈客户端，远端发送在部署前关闭。下文保留 0.19 及其前置方案的原始验收记录。

The six files in `Sources/RiftletFeedback` and six inherited XCTest files in `tests/RiftletFeedbackTests` are reused from the same owner’s Riftlet repository, at `b5a412f6d37378b7cfef56e2f1e9524cc9b1ac6e`, under the user’s explicit request to share the existing feedback system. The upstream repository does not contain a blanket LICENSE; this is owner-authorized reuse, not a claim of an independent open-source grant.

The product adapter adds an optional closed product discriminator (`riftlet`, `saytile`, `nearpane`) to the frozen envelope. Absent product preserves legacy encoding byte for byte. Saytile must always supply `saytile`; separate Application Support directories and Keychain namespaces isolate drafts, outboxes and capabilities. No ASR archive, transcription, recording or raw diagnostic log is inspected by this module.

The outbox, capability lifecycle, unknown delivery protection, deletion workflow, privacy bounds and serial SQLite storage are inherited. The UI remains supplied by each product.

The adaptation keeps SQLite and the process lock in a resource owner held exclusively by the store actor. Its ordinary destructor closes both resources; this preserves Swift 6 isolation and avoids a confirmed cross-module release-optimizer cycle in isolated actor destruction. Keychain service-name visibility is internal to the module for namespace tests; storage behavior is unchanged. The controller regression fixture uses only temporary SQLite files and in-memory capabilities, including explicit storage failures and a pending transport; it never sends feedback or reads the user's Keychain or archives.

## Service dependency and release boundary

Saytile 0.19's structured `product=saytile` requires [Riftlet PR #104](https://github.com/haohongfei2001-png/Riftlet/pull/104). The destination remains the existing **private** `haohongfei2001-png/Riftlet-Feedback` repository. Fixed labels `product:riftlet`, `product:saytile`, and `product:nearpane` have been created and read back. No feedback Issue was submitted during preparation.

Service source review and tests are separate from deployment. On 2026-11-15 Wrangler 4.162.0 reported no authenticated session; the existing repository has no deployment workflow or Actions secrets. Cloudflare migration/deployment and native-to-private-Issue acceptance are **BLOCKED / NOT_RUN**. Completing one login to the already authorized Cloudflare account is the only owner action; do not paste API secrets into chat. No new account, paid plan or infrastructure is required by this change.

Do not install/announce the feedback-enabled candidate as working until the existing D1 additive migration and reviewed Workers are deployed, and one synthetic Saytile submission is confirmed in the private repository. Keep the installed 0.18 candidate and its data unchanged in the meantime. Source/build/native fixtures may be completed independently. Legacy omitted-product requests retain their exact encoding and are treated as Riftlet; this change does not retrofit unrelated Nearpane client code or reinterpret old user feedback.

## Reliability checks

The actual settings controller preserves drafts across rapid edits and quit, waits for durable enqueue but not a hanging HTTP request, and reopens editing if quit is cancelled. Storage failures retain the draft. A blocked deletion retains an explicit retry action; a pending deletion is never reported as deleted until confirmed. Synthetic acceptance never accesses the audio archive, API keys, system clipboard or a real feedback endpoint.
