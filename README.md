# Saytile signed update feeds

These are separate default-channel Sparkle feeds for `app.saytile.mac` (`standard/`) and `app.saytile.mac.mandarin-candidate` (`mandarin/`). Empty feeds mean **no approved downloadable update**, not a claim of a stable public release.

Only approved, source-bound, tested packages for the same bundle identity may be added. Every package and modified appcast must be signed with the Saytile-specific Ed25519 key in the maintainer Keychain account `app.saytile.updates.v1`; the private key is never committed or exported by these tools. The public key is pinned in `packaging/update-channels.json` on the product branch. Sparkle also verifies the application code signature before installation.

No automatic publishing workflow runs on this branch. A development PR, passing CI or candidate build does not authorize a release. Keep the published feed unchanged until the release is explicitly authorized. Preserve old items where still supported; never lower build numbers or move a candidate item into the formal feed.

Use the product's `scripts/prepare-updater.sh` and official `bin/sign_update --account app.saytile.updates.v1` to sign approved archives and appcasts. Verify package source, bundle ID, increasing build, code signature/notarization, archive signature and full isolated update/rollback evidence before publication. No source archives, credentials, model weights or user data belong here.
