import Foundation

/// Represents an output of a transaction
struct TransactionOutput: Codable, Hashable {
    /// Recipient's payment address
    let address: String

    /// Amount in satoshi-like units (1 MeshToken = 100,000,000 units)
    let amount: UInt64

    /// Optional script for advanced conditions (future extension)
    var scriptPubKey: Data?

    /// Memberwise initializer
    init(address: String, amount: UInt64, scriptPubKey: Data? = nil) {
        self.address = address
        self.amount = amount
        self.scriptPubKey = scriptPubKey
    }
}

// MARK: - Amount Utilities
extension TransactionOutput {
    /// Convert units to human-readable MeshTokens (1 MT = 10^8 units)
    var amountInTokens: Double {
        Double(amount) / 100_000_000.0
    }

    /// Create output from token amount
    static func fromTokens(address: String, tokens: Double) -> TransactionOutput {
        let units = UInt64(tokens * 100_000_000.0)
        return TransactionOutput(address: address, amount: units)
    }
}
