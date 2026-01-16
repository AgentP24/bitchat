import Foundation

/// Represents an input to a transaction, referencing a previous UTXO
struct TransactionInput: Codable, Hashable {
    /// ID of the transaction containing the UTXO being spent
    let previousTxId: String

    /// Index of the output in the previous transaction
    let outputIndex: UInt32

    /// Signature proving ownership of the UTXO (Ed25519 or ECDSA)
    /// Signature is over: SHA-256(txId || outputIndex || timestamp)
    var signature: Data?

    /// Optional script for advanced conditions (future extension)
    var scriptSig: Data?

    /// Memberwise initializer
    init(previousTxId: String, outputIndex: UInt32, signature: Data? = nil, scriptSig: Data? = nil) {
        self.previousTxId = previousTxId
        self.outputIndex = outputIndex
        self.signature = signature
        self.scriptSig = scriptSig
    }

    /// Create a unique identifier for this input reference
    var utxoReference: String {
        "\(previousTxId):\(outputIndex)"
    }
}
