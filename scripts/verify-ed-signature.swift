import CryptoKit
import Foundation

// Usage: verify-ed-signature.swift <public-key> <signature> <file>, both keys in base64.
// Python's standard library has no Ed25519, and this must check what Sparkle will check.
let arguments = CommandLine.arguments
guard arguments.count == 4,
      let publicKey = Data(base64Encoded: arguments[1]),
      let signature = Data(base64Encoded: arguments[2]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
      let file = try? Data(contentsOf: URL(fileURLWithPath: arguments[3])),
      key.isValidSignature(signature, for: file)
else {
    print("The signature does not match this key and file.")
    exit(1)
}
print("The signature matches.")
