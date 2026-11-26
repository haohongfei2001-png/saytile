import CryptoKit
import Foundation

// Public verification only. No Keychain access and no private-key input.
guard CommandLine.arguments.count == 4,
      let key = Data(base64Encoded: CommandLine.arguments[1]), key.count == 32,
      let signature = Data(base64Encoded: CommandLine.arguments[2]), signature.count == 64 else {
    exit(64)
}
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]), options: .mappedIfSafe)
guard publicKey.isValidSignature(signature, for: bytes) else { exit(65) }
print("ED25519_PUBLIC_VERIFICATION_PASS")
