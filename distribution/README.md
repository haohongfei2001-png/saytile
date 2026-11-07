# Developer ID distribution for the verified Saytile candidate

`developer-id.py` promotes a copy of the pinned no-api.9.1 candidate for future authorized distribution. The source revision is `0a0cdecab8eb099e1dc3bb21b4c15ba5c30c93f0`. The package, bundle identifier, release version, executable hash, arm64 architecture, resource contents and original code signature are checked before signing. The expected input DMG SHA-256 is `9d157becfa40e214b579036b03a178cffa85c96c6f0a54923809bd8110938339`. [Candidate and recorded checksums](../deliverables/no-api.9.1/README.md)

**Current verification covers offline preflight.** The existing candidate is ad hoc signed. Developer ID signing, Apple notarization, ticket stapling and public distribution remain pending an authorized publisher with the appropriate Apple account. This process addresses macOS distribution. Live cloud connection, speech quality and final product acceptance retain their existing status. [Installation and acceptance scope](../docs/V1-INSTALL.md)

Run the offline checks from the repository root. They inspect the pinned DMG through a hidden read-only mount, copy its app into a temporary directory and validate both copies. The test additionally verifies refusal paths using synthetic files and restricts subprocesses to the offline inspection tools.

```sh
python3 distribution/developer-id.py preflight
python3 distribution/test-preflight.py
```

## Future authorized release

The publisher needs the exact SHA-1 identifier of their **Developer ID Application** certificate, its Team ID and an existing, authorized `notarytool` Keychain profile. Supply the profile name through `--profile`. Apple documents credential preparation and submission for an authorized account. [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

1. Choose a fresh **private work directory** under an existing parent. `submit` verifies and copies the pinned app, signs the copy with Hardened Runtime and a secure timestamp, checks the Apple Developer ID certificate requirement, Team ID and Audio Input entitlement, builds and signs a new DMG, then submits that outer container once. This candidate has one native executable. Unexpected nested Mach-O code causes refusal. New package layouts must be reviewed for inside-out signing. [Apple code-signing instructions](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac), [Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input), [DMG packaging](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

   ```sh
   python3 distribution/developer-id.py submit \
     --identity '<exact 40-hex certificate SHA-1>' --team '<10-character Team ID>' \
     --profile '<authorized profile name>' --work '/path/to/new-private-work-directory'
   ```

2. Preserve the returned submission ID and private work directory. The submitted image is staging material. If the submission reply is ambiguous, inspect the stored reply and Apple submission history before any further action. Once Apple has completed processing, `finish` checks the existing job and its log against the submitted DMG hash. It requires `Accepted`, staples and validates the ticket on a fresh copy, verifies the DMG signature and integrity, remounts read-only, checks the enclosed app and asks Gatekeeper to assess the image and app. Only then does it publish the verified file atomically at a fresh destination and print its SHA-256. `finish` can be repeated for the same job if the service was still processing. [Apple notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Gatekeeper DMG assessment](https://developer.apple.com/library/archive/technotes/tn2206/)

   ```sh
   python3 distribution/developer-id.py finish \
     --profile '<authorized profile name>' --work '/path/to/new-private-work-directory' \
     --output '/path/to/new/Saytile-Developer-ID.dmg'
   ```

The publisher reviews `notary-log.json`, retains the successful checksum and submission ID, and verifies the downloaded release on an independent Mac before consumer rollout. The final image's instructions cover RC1 preservation, complete stopped-directory backup and rollback, and explicit authorization for cloud audio. macOS microphone and Accessibility permissions remain user-managed. The hardened-runtime entitlement enables requesting audio input; system consent remains necessary. [Apple media authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
