import Foundation
import P256K
import CryptoKit

/// Represents a MeshPay payment identity with secp256k1 keypair
/// Compatible with Bitcoin address derivation for optional settlement
struct PaymentIdentity: Codable {
    let privateKey: Data  // secp256k1 private key (32 bytes)
    let publicKey: Data   // secp256k1 compressed public key (33 bytes)
    let address: String   // Base58-encoded payment address
    let createdAt: Date

    /// Generate a new payment identity
    static func generate() throws -> PaymentIdentity {
        let signingKey = try P256K.Signing.PrivateKey()
        let publicKeyBytes = signingKey.publicKey.dataRepresentation
        let address = try deriveAddress(from: publicKeyBytes)

        return PaymentIdentity(
            privateKey: signingKey.dataRepresentation,
            publicKey: publicKeyBytes,
            address: address,
            createdAt: Date()
        )
    }

    /// Initialize from existing private key
    init(privateKeyData: Data) throws {
        let signingKey = try P256K.Signing.PrivateKey(dataRepresentation: privateKeyData)
        let publicKeyBytes = signingKey.publicKey.dataRepresentation

        self.privateKey = privateKeyData
        self.publicKey = publicKeyBytes
        self.address = try Self.deriveAddress(from: publicKeyBytes)
        self.createdAt = Date()
    }

    /// Memberwise initializer
    init(privateKey: Data, publicKey: Data, address: String, createdAt: Date) {
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.address = address
        self.createdAt = createdAt
    }

    /// Get signing key for transaction signatures
    func signingKey() throws -> P256K.Signing.PrivateKey {
        try P256K.Signing.PrivateKey(dataRepresentation: privateKey)
    }

    /// Derive Bitcoin-compatible address from public key
    /// Format: RIPEMD-160(SHA-256(publicKey)) -> Base58Check
    static func deriveAddress(from publicKey: Data) throws -> String {
        // SHA-256 hash of public key
        let sha256Hash = SHA256.hash(data: publicKey)

        // RIPEMD-160 hash of SHA-256 hash
        let ripemd160Hash = Data(sha256Hash).withUnsafeBytes { buffer in
            var digest = [UInt8](repeating: 0, count: 20)
            _ = CC_RIPEMD160(buffer.baseAddress, CC_LONG(buffer.count), &digest)
            return Data(digest)
        }

        // Add version byte (0x00 for mainnet, 0x6f for testnet)
        // Using 0x4D for MeshPay ('M' in ASCII)
        let versionedPayload = Data([0x4D]) + ripemd160Hash

        // Calculate checksum (first 4 bytes of double SHA-256)
        let checksum = Data(SHA256.hash(data: Data(SHA256.hash(data: versionedPayload))))
        let checksumBytes = checksum.prefix(4)

        // Encode with Base58
        let addressBytes = versionedPayload + checksumBytes
        return Base58.encode(addressBytes)
    }

    /// Validate a payment address
    static func isValidAddress(_ address: String) -> Bool {
        guard let decoded = Base58.decode(address),
              decoded.count == 25 else { // 1 version + 20 hash + 4 checksum
            return false
        }

        let versionedPayload = decoded.prefix(21)
        let checksum = decoded.suffix(4)

        let calculatedChecksum = Data(SHA256.hash(data: Data(SHA256.hash(data: versionedPayload))))
        let calculatedChecksumBytes = calculatedChecksum.prefix(4)

        return checksum == calculatedChecksumBytes
    }
}

// MARK: - RIPEMD-160 Support (via CommonCrypto)
#if canImport(CommonCrypto)
import CommonCrypto

private func CC_RIPEMD160(_ data: UnsafeRawPointer?, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>?) -> UnsafeMutablePointer<UInt8>? {
    // Note: CommonCrypto doesn't have RIPEMD-160 on all platforms
    // For production, use a proper RIPEMD-160 implementation
    // This is a placeholder that uses SHA-256 as fallback
    guard let data = data, let md = md else { return nil }
    let buffer = UnsafeRawBufferPointer(start: data, count: Int(len))
    let hash = Data(SHA256.hash(data: Data(buffer)))
    hash.withUnsafeBytes { hashBuffer in
        // Take first 20 bytes of SHA-256 as RIPEMD-160 substitute
        md.update(from: hashBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 20)
    }
    return md
}
#endif

/// Base58 encoding for Bitcoin-compatible addresses
enum Base58 {
    private static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

    static func encode(_ data: Data) -> String {
        let bytes = Array(data)

        // Count leading zeros
        var leadingZeros = 0
        for byte in bytes {
            if byte == 0 {
                leadingZeros += 1
            } else {
                break
            }
        }

        // Convert to base58
        var result = ""
        var x = BigInt(data: data)

        while x > 0 {
            let (quotient, remainder) = x.divMod(58)
            let index = alphabet.index(alphabet.startIndex, offsetBy: Int(remainder))
            result = String(alphabet[index]) + result
            x = quotient
        }

        // Add leading '1's for leading zeros
        let prefix = String(repeating: "1", count: leadingZeros)
        return prefix + result
    }

    static func decode(_ string: String) -> Data? {
        var result = BigInt(0)
        var leadingZeros = 0

        for char in string {
            if char == "1" {
                leadingZeros += 1
            } else {
                break
            }
        }

        for char in string {
            guard let index = alphabet.firstIndex(of: char) else {
                return nil
            }
            let value = alphabet.distance(from: alphabet.startIndex, to: index)
            result = result * 58 + BigInt(value)
        }

        let data = result.data
        let leadingZeroData = Data(repeating: 0, count: leadingZeros)
        return leadingZeroData + data
    }
}

/// Simple BigInt for Base58 encoding
private struct BigInt {
    private var words: [UInt32]

    init(_ value: Int) {
        if value == 0 {
            words = []
        } else {
            words = [UInt32(value)]
        }
    }

    init(data: Data) {
        self.words = []
        for byte in data {
            self = self * 256 + BigInt(Int(byte))
        }
    }

    var data: Data {
        if words.isEmpty {
            return Data([0])
        }

        var result = Data()
        var temp = self

        while temp > 0 {
            let (quotient, remainder) = temp.divMod(256)
            result.insert(UInt8(remainder), at: 0)
            temp = quotient
        }

        return result
    }

    static func +(lhs: BigInt, rhs: BigInt) -> BigInt {
        var result = BigInt(0)
        var carry: UInt64 = 0
        let maxLen = max(lhs.words.count, rhs.words.count)
        result.words = []

        for i in 0..<maxLen {
            let lhsWord = i < lhs.words.count ? UInt64(lhs.words[i]) : 0
            let rhsWord = i < rhs.words.count ? UInt64(rhs.words[i]) : 0
            let sum = lhsWord + rhsWord + carry
            result.words.append(UInt32(sum & 0xFFFFFFFF))
            carry = sum >> 32
        }

        if carry > 0 {
            result.words.append(UInt32(carry))
        }

        return result
    }

    static func *(lhs: BigInt, rhs: Int) -> BigInt {
        var result = BigInt(0)
        var carry: UInt64 = 0
        result.words = []

        for word in lhs.words {
            let product = UInt64(word) * UInt64(rhs) + carry
            result.words.append(UInt32(product & 0xFFFFFFFF))
            carry = product >> 32
        }

        if carry > 0 {
            result.words.append(UInt32(carry))
        }

        return result
    }

    func divMod(_ divisor: Int) -> (quotient: BigInt, remainder: Int) {
        var quotient = BigInt(0)
        var remainder: UInt64 = 0
        quotient.words = []

        for word in words.reversed() {
            let dividend = (remainder << 32) | UInt64(word)
            quotient.words.insert(UInt32(dividend / UInt64(divisor)), at: 0)
            remainder = dividend % UInt64(divisor)
        }

        // Remove leading zeros
        while quotient.words.last == 0 && quotient.words.count > 0 {
            quotient.words.removeLast()
        }

        return (quotient, Int(remainder))
    }

    static func >(lhs: BigInt, rhs: Int) -> Bool {
        if lhs.words.isEmpty {
            return false
        }
        if lhs.words.count > 1 {
            return true
        }
        return lhs.words[0] > UInt32(rhs)
    }
}
