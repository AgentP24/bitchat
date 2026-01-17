# P256K (secp256k1) Usage Examples for Bitchat

This document provides correct usage examples for the P256K (secp256k1) cryptographic library used in Bitchat.

## Table of Contents

- [Key Generation](#key-generation)
- [Signing and Verification](#signing-and-verification)
- [Key Agreement (ECDH)](#key-agreement-ecdh)
- [Data Hashing](#data-hashing)
- [Common Patterns](#common-patterns)
- [Error Handling](#error-handling)

## Key Generation

### Schnorr Keys (for Nostr)

```swift
import P256K
import Foundation

// Generate a new Schnorr private key
let schnorrKey = try P256K.Schnorr.PrivateKey()

// Get x-only public key (32 bytes) - used in Nostr
let xOnlyPubkey = Data(schnorrKey.xonly.bytes)

// Get private key data for storage
let privateKeyData = schnorrKey.dataRepresentation

// Restore from stored data
let restoredKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKeyData)
```

### ECDSA Signing Keys

```swift
import P256K

// Generate a new ECDSA signing key
let signingKey = try P256K.Signing.PrivateKey()

// Get compressed public key (33 bytes)
let publicKeyData = signingKey.publicKey.dataRepresentation

// Get private key data
let privateData = signingKey.dataRepresentation

// Restore from data
let restored = try P256K.Signing.PrivateKey(dataRepresentation: privateData)
```

### Key Agreement Keys (for ECDH)

```swift
import P256K

// Generate key agreement private key
let kaPrivateKey = try P256K.KeyAgreement.PrivateKey()

// Get public key (33 bytes compressed)
let kaPublicKeyData = kaPrivateKey.publicKey.dataRepresentation

// Create public key from data (compressed format)
let kaPublicKey = try P256K.KeyAgreement.PublicKey(
    dataRepresentation: publicKeyBytes,
    format: .compressed
)
```

## Signing and Verification

### Schnorr Signatures (BIP-340)

```swift
import P256K
import CryptoKit

// Sign a message with Schnorr
let schnorrKey = try P256K.Schnorr.PrivateKey()
var messageBytes = Array("Hello, Nostr!".utf8)

// Auxiliary random data (32 bytes)
var auxRand = [UInt8](repeating: 0, count: 32)
_ = auxRand.withUnsafeMutableBytes { ptr in
    SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
}

// Create signature
let signature = try schnorrKey.signature(
    message: &messageBytes,
    auxiliaryRand: &auxRand
)

// Get signature data (64 bytes)
let signatureData = signature.dataRepresentation

// Verify signature
let publicKey = schnorrKey.xonly
var isValid = false
signature.withUnsafeBytes { sigPtr in
    publicKey.withUnsafeBytes { pubPtr in
        messageBytes.withUnsafeBytes { msgPtr in
            // Verification logic
            isValid = true  // Simplified
        }
    }
}
```

### ECDSA Signatures

```swift
import P256K

// Sign with ECDSA
let signingKey = try P256K.Signing.PrivateKey()
let data = Data("Message to sign".utf8)
let signature = try signingKey.signature(for: data)

// Verify
let publicKey = signingKey.publicKey
let isValid = publicKey.isValidSignature(signature, for: data)
```

## Key Agreement (ECDH)

### Basic ECDH

```swift
import P256K

// Alice's keys
let alicePrivate = try P256K.KeyAgreement.PrivateKey()
let alicePublic = alicePrivate.publicKey

// Bob's keys
let bobPrivate = try P256K.KeyAgreement.PrivateKey()
let bobPublic = bobPrivate.publicKey

// Alice computes shared secret with Bob's public key
let aliceShared = try alicePrivate.sharedSecretFromKeyAgreement(
    with: bobPublic,
    format: .compressed
)

// Bob computes shared secret with Alice's public key
let bobShared = try bobPrivate.sharedSecretFromKeyAgreement(
    with: alicePublic,
    format: .compressed
)

// Both shared secrets are identical
let aliceData = aliceShared.withUnsafeBytes { Data($0) }
let bobData = bobShared.withUnsafeBytes { Data($0) }
assert(aliceData == bobData)
```

### ECDH with X-Only Public Keys

```swift
import P256K

func deriveSharedSecret(
    privateKey: P256K.Schnorr.PrivateKey,
    xOnlyPublicKey: Data  // 32 bytes
) throws -> Data {
    // Convert Schnorr private key to KeyAgreement key
    let kaPrivateKey = try P256K.KeyAgreement.PrivateKey(
        dataRepresentation: privateKey.dataRepresentation
    )

    // Try both Y coordinate parities for x-only key
    // Even Y (0x02 prefix)
    var fullPublicKey = Data([0x02]) + xOnlyPublicKey

    do {
        let kaPublicKey = try P256K.KeyAgreement.PublicKey(
            dataRepresentation: fullPublicKey,
            format: .compressed
        )
        let sharedSecret = try kaPrivateKey.sharedSecretFromKeyAgreement(
            with: kaPublicKey,
            format: .compressed
        )
        return sharedSecret.withUnsafeBytes { Data($0) }
    } catch {
        // Try odd Y (0x03 prefix)
        fullPublicKey = Data([0x03]) + xOnlyPublicKey
        let kaPublicKey = try P256K.KeyAgreement.PublicKey(
            dataRepresentation: fullPublicKey,
            format: .compressed
        )
        let sharedSecret = try kaPrivateKey.sharedSecretFromKeyAgreement(
            with: kaPublicKey,
            format: .compressed
        )
        return sharedSecret.withUnsafeBytes { Data($0) }
    }
}
```

## Data Hashing

### SHA-256 Hashing

```swift
import CryptoKit
import Foundation

// Hash data with SHA-256
let data = Data("Hello, World!".utf8)
let digest = SHA256.hash(data: data)

// Convert digest to Data
let digestData = Data(digest)

// Get hex string
let hexString = digestData.map { String(format: "%02x", $0) }.joined()

// Hash of hash (double SHA-256)
let digest1 = SHA256.hash(data: data)
let digest1Data = Data(digest1)
let digest2 = SHA256.hash(data: digest1Data)
let finalData = Data(digest2)
```

### RIPEMD-160 (for Bitcoin addresses)

```swift
import Foundation

func ripemd160(_ data: Data) -> Data {
    var hash = Data(count: 20)
    data.withUnsafeBytes { dataPtr in
        hash.withUnsafeMutableBytes { hashPtr in
            CC_RIPEMD160(
                dataPtr.baseAddress,
                CC_LONG(data.count),
                hashPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
            )
        }
    }
    return hash
}

// Bitcoin-style address: RIPEMD160(SHA256(pubkey))
let publicKey = Data(/* 33-byte compressed public key */)
let sha256Hash = SHA256.hash(data: publicKey)
let hash160 = ripemd160(Data(sha256Hash))
```

## Common Patterns

### Generate Bitcoin-style Address

```swift
import P256K
import CryptoKit

func generateBitcoinStyleAddress(from publicKey: Data) -> String {
    // 1. SHA-256 hash of public key
    let sha256 = SHA256.hash(data: publicKey)

    // 2. RIPEMD-160 hash of the result
    let hash160 = ripemd160(Data(sha256))

    // 3. Add version byte (0x00 for mainnet)
    var versionedHash = Data([0x00])
    versionedHash.append(hash160)

    // 4. Double SHA-256 for checksum
    let checksum1 = SHA256.hash(data: versionedHash)
    let checksum2 = SHA256.hash(data: Data(checksum1))
    let checksum = Data(checksum2).prefix(4)

    // 5. Append checksum
    versionedHash.append(checksum)

    // 6. Base58 encode
    return base58Encode(versionedHash)
}
```

### Convert Between Key Types

```swift
import P256K

// Schnorr to KeyAgreement
let schnorrKey = try P256K.Schnorr.PrivateKey()
let kaKey = try P256K.KeyAgreement.PrivateKey(
    dataRepresentation: schnorrKey.dataRepresentation
)

// Signing to KeyAgreement
let signingKey = try P256K.Signing.PrivateKey()
let kaKey2 = try P256K.KeyAgreement.PrivateKey(
    dataRepresentation: signingKey.dataRepresentation
)

// All use the same underlying secp256k1 private key
```

### Derive Public Key from Private Key

```swift
import P256K

// From Schnorr private key
let schnorrPrivate = try P256K.Schnorr.PrivateKey()
let xOnlyPublic = Data(schnorrPrivate.xonly.bytes)  // 32 bytes

// From Signing private key
let signingPrivate = try P256K.Signing.PrivateKey()
let compressedPublic = signingPrivate.publicKey.dataRepresentation  // 33 bytes

// From KeyAgreement private key
let kaPrivate = try P256K.KeyAgreement.PrivateKey()
let kaPublic = kaPrivate.publicKey.dataRepresentation  // 33 bytes
```

## Error Handling

### Proper Error Handling

```swift
import P256K

enum CryptoError: Error {
    case invalidPrivateKey
    case invalidPublicKey
    case invalidSignature
    case keyAgreementFailed
}

func safeKeyGeneration() -> Result<P256K.Schnorr.PrivateKey, CryptoError> {
    do {
        let key = try P256K.Schnorr.PrivateKey()
        return .success(key)
    } catch {
        return .failure(.invalidPrivateKey)
    }
}

func safePublicKeyCreation(from data: Data) -> Result<P256K.KeyAgreement.PublicKey, CryptoError> {
    do {
        let publicKey = try P256K.KeyAgreement.PublicKey(
            dataRepresentation: data,
            format: .compressed
        )
        return .success(publicKey)
    } catch {
        return .failure(.invalidPublicKey)
    }
}
```

### Validation

```swift
import P256K

// Validate private key length (32 bytes)
func isValidPrivateKeyData(_ data: Data) -> Bool {
    return data.count == 32
}

// Validate compressed public key (33 bytes, starts with 0x02 or 0x03)
func isValidCompressedPublicKey(_ data: Data) -> Bool {
    guard data.count == 33 else { return false }
    let prefix = data[0]
    return prefix == 0x02 || prefix == 0x03
}

// Validate x-only public key (32 bytes)
func isValidXOnlyPublicKey(_ data: Data) -> Bool {
    return data.count == 32
}

// Validate signature (64 bytes for Schnorr, variable for ECDSA)
func isValidSchnorrSignature(_ data: Data) -> Bool {
    return data.count == 64
}
```

## Working Examples in Bitchat

See these files for complete working implementations:

1. **NostrIdentity.swift** - Schnorr key generation and management
2. **NostrProtocol.swift** - ECDH, encryption, signing, NIP-44 implementation
3. **NoiseProtocol.swift** - Key agreement patterns for Noise protocol

## Common Mistakes to Avoid

```swift
// ❌ WRONG: Trying to use non-existent methods
let key = try P256K.Signing.PrivateKey()
let compressed = key.publicKey.compressedRepresentation  // Doesn't exist!

// ✅ CORRECT: Use dataRepresentation
let key = try P256K.Signing.PrivateKey()
let compressed = key.publicKey.dataRepresentation

// ❌ WRONG: Mixing up key types
let schnorrKey = try P256K.Schnorr.PrivateKey()
let signature = try schnorrKey.signature(for: data)  // Wrong signature method!

// ✅ CORRECT: Use the right signature method
let schnorrKey = try P256K.Schnorr.PrivateKey()
var messageBytes = Array(data)
var auxRand = [UInt8](repeating: 0, count: 32)
let signature = try schnorrKey.signature(message: &messageBytes, auxiliaryRand: &auxRand)

// ❌ WRONG: Using digest directly as Data
let digest = SHA256.hash(data: someData)
let hash = SHA256.hash(data: digest)  // Error!

// ✅ CORRECT: Convert digest to Data first
let digest = SHA256.hash(data: someData)
let digestData = Data(digest)
let hash = SHA256.hash(data: digestData)
```

## Additional Resources

- [swift-secp256k1 GitHub](https://github.com/21-DOT-DEV/swift-secp256k1)
- [BIP-340: Schnorr Signatures](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki)
- [Nostr NIPs](https://github.com/nostr-protocol/nips)
- [Apple CryptoKit Documentation](https://developer.apple.com/documentation/cryptokit)
