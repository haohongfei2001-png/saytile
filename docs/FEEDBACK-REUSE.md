# Feedback core reuse

The six files in `Sources/RiftletFeedback` and six inherited XCTest files in `tests/RiftletFeedbackTests` are reused from the same owner’s Riftlet repository, at `b5a412f6d37378b7cfef56e2f1e9524cc9b1ac6e`, under the user’s explicit request to share the existing feedback system. The upstream repository does not contain a blanket LICENSE; this is owner-authorized reuse, not a claim of an independent open-source grant.

The product adapter adds an optional closed product discriminator (`riftlet`, `saytile`, `nearpane`) to the frozen envelope. Absent product preserves legacy encoding byte for byte. Saytile must always supply `saytile`; separate Application Support directories and Keychain namespaces isolate drafts, outboxes and capabilities. No ASR archive, transcription, recording or raw diagnostic log is inspected by this module.

The outbox, capability lifecycle, unknown delivery protection, deletion workflow, privacy bounds and serial SQLite storage are inherited. The UI remains supplied by each product.

The adaptation uses an isolated actor destructor for the SQLite handle under Swift 6 strict concurrency. Keychain service-name visibility is internal to the module for namespace tests; storage behavior is unchanged. The controller regression fixture uses only temporary SQLite files and in-memory capabilities, including explicit storage failures and a pending transport; it never sends feedback or reads the user's Keychain or archives.
