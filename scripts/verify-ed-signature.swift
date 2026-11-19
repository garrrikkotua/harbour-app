// Verifies an EdDSA (ed25519) signature with a public key, independently of
// the private key that produced it. Used by make-appcast.sh to prove a release
// ZIP will verify against the SUPublicEDKey embedded in the shipped app.
//
// Usage: swift scripts/verify-ed-signature.swift <public-key-base64> <signature-base64> <file>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
      let keyData = Data(base64Encoded: args[1]),
      let signature = Data(base64Encoded: args[2]),
      let file = FileManager.default.contents(atPath: args[3]) else {
    FileHandle.standardError.write(Data("usage: verify-ed-signature <public-key-b64> <signature-b64> <file>\n".utf8))
    exit(2)
}
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    guard key.isValidSignature(signature, for: file) else {
        FileHandle.standardError.write(Data("signature does not match the public key\n".utf8))
        exit(1)
    }
    print("signature verified")
} catch {
    FileHandle.standardError.write(Data("invalid public key: \(error)\n".utf8))
    exit(2)
}
