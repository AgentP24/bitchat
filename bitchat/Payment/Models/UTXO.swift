import Foundation

/// Represents an Unspent Transaction Output (UTXO)
struct UTXO: Codable, Identifiable {
    /// Unique identifier: txId:outputIndex
    var id: String {
        "\(transactionId):\(outputIndex)"
    }

    /// ID of the transaction that created this UTXO
    let transactionId: String

    /// Index of this output in the transaction
    let outputIndex: UInt32

    /// The actual output data
    let output: TransactionOutput

    /// Block height or confirmation count when added
    let height: UInt32

    /// Timestamp when this UTXO was created
    let createdAt: Date

    /// Whether this UTXO has been spent (for tracking)
    var isSpent: Bool

    /// Transaction ID that spent this UTXO (if spent)
    var spentBy: String?

    /// Memberwise initializer
    init(
        transactionId: String,
        outputIndex: UInt32,
        output: TransactionOutput,
        height: UInt32,
        createdAt: Date = Date(),
        isSpent: Bool = false,
        spentBy: String? = nil
    ) {
        self.transactionId = transactionId
        self.outputIndex = outputIndex
        self.output = output
        self.height = height
        self.createdAt = createdAt
        self.isSpent = isSpent
        self.spentBy = spentBy
    }

    /// Create UTXOs from a transaction
    static func fromTransaction(_ transaction: Transaction, height: UInt32) -> [UTXO] {
        transaction.outputs.enumerated().map { index, output in
            UTXO(
                transactionId: transaction.id,
                outputIndex: UInt32(index),
                output: output,
                height: height,
                createdAt: Date(timeIntervalSince1970: Double(transaction.timestamp) / 1000.0)
            )
        }
    }

    /// Mark this UTXO as spent
    mutating func markSpent(by transactionId: String) {
        isSpent = true
        spentBy = transactionId
    }
}

/// Collection of UTXOs for a specific address
struct UTXOSet: Codable {
    /// Map of UTXO ID to UTXO
    private(set) var utxos: [String: UTXO]

    init() {
        self.utxos = [:]
    }

    init(utxos: [String: UTXO]) {
        self.utxos = utxos
    }

    /// Add a UTXO to the set
    mutating func add(_ utxo: UTXO) {
        utxos[utxo.id] = utxo
    }

    /// Remove a UTXO from the set
    mutating func remove(_ utxoId: String) {
        utxos.removeValue(forKey: utxoId)
    }

    /// Mark a UTXO as spent
    mutating func markSpent(_ utxoId: String, by transactionId: String) {
        utxos[utxoId]?.markSpent(by: transactionId)
    }

    /// Get all unspent UTXOs
    func unspent() -> [UTXO] {
        utxos.values.filter { !$0.isSpent }
    }

    /// Get unspent UTXOs for a specific address
    func unspent(for address: String) -> [UTXO] {
        unspent().filter { $0.output.address == address }
    }

    /// Calculate total balance for an address
    func balance(for address: String) -> UInt64 {
        unspent(for: address).reduce(0) { $0 + $1.output.amount }
    }

    /// Select UTXOs for a payment (simple greedy selection)
    func selectForPayment(from address: String, amount: UInt64) -> [UTXO]? {
        let available = unspent(for: address).sorted { $0.output.amount > $1.output.amount }
        var selected: [UTXO] = []
        var total: UInt64 = 0

        for utxo in available {
            selected.append(utxo)
            total += utxo.output.amount

            if total >= amount {
                return selected
            }
        }

        // Insufficient funds
        return nil
    }

    /// Apply a transaction to the UTXO set
    mutating func applyTransaction(_ transaction: Transaction, height: UInt32) {
        // Remove spent UTXOs
        for input in transaction.inputs {
            markSpent(input.utxoReference, by: transaction.id)
        }

        // Add new UTXOs
        let newUtxos = UTXO.fromTransaction(transaction, height: height)
        for utxo in newUtxos {
            add(utxo)
        }
    }

    /// Revert a transaction from the UTXO set
    mutating func revertTransaction(_ transaction: Transaction) {
        // Re-add spent UTXOs (mark as unspent)
        for input in transaction.inputs {
            if var utxo = utxos[input.utxoReference] {
                utxo.isSpent = false
                utxo.spentBy = nil
                utxos[input.utxoReference] = utxo
            }
        }

        // Remove UTXOs created by this transaction
        for (index, _) in transaction.outputs.enumerated() {
            let utxoId = "\(transaction.id):\(index)"
            remove(utxoId)
        }
    }
}
