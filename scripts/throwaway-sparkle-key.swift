import CryptoKit
import Foundation

// Prints "<private> <public>" for dry runs. `generate_keys` would write to the login Keychain.
let key = Curve25519.Signing.PrivateKey()
let parts = [key.rawRepresentation, key.publicKey.rawRepresentation].map { $0.base64EncodedString() }
print(parts.joined(separator: " "))
