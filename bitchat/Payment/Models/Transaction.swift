import Foundation
import CryptoKit
import P256K

/// Represents a MeshPay transaction in the UTXO model
struct Transaction: Codable, Identifiable {
    /// Unique transaction identifier (SHA-256 hash of transaction data)
    let id: String

    /// Version of transaction format (v2 for multi-currency)
    let version: UInt8

    /// Currency code (4 bytes, e.g., "MTOK", "WBTC")
    let currency: String

    /// Inputs consuming previous UTXOs
    var inputs: [TransactionInput]

    /// Outputs creating new UTXOs
    let outputs: [TransactionOutput]

    /// Transaction fee in units (difference between inputs and outputs)
    let fee: UInt64

    /// Unix timestamp in milliseconds
    let timestamp: UInt64

    /// Optional memo/note (encrypted or public)
    var memo: String?

    /// Sender's public key for verification
    let senderPublicKey: Data

    /// Transaction signature (Ed25519 over transaction hash)
    var signature: Data?

    /// Number of confirmations in the mesh (updated as it propagates)
    var confirmations: UInt32

    /// Transaction type (normal, atomic swap, etc.)
    var txType: TransactionType

    /// Memberwise initializer
    init(
        id: String,
        version: UInt8 = 2,
        currency: String = "MTOK",
        inputs: [TransactionInput],
        outputs: [TransactionOutput],
        fee: UInt64,
        timestamp: UInt64,
        memo: String? = nil,
        senderPublicKey: Data,
        signature: Data? = nil,
        confirmations: UInt32 = 0,
        txType: TransactionType = .standard
    ) {
        self.id = id
        self.version = version
        self.currency = currency
        self.inputs = inputs
        self.outputs = outputs
        self.fee = fee
        self.timestamp = timestamp
        self.memo = memo
        self.senderPublicKey = senderPublicKey
        self.signature = signature
        self.confirmations = confirmations
        self.txType = txType
    }

    /// Create a new transaction (calculates ID automatically)
    static func create(
        currency: String = "MTOK",
        inputs: [TransactionInput],
        outputs: [TransactionOutput],
        fee: UInt64,
        memo: String? = nil,
        senderPublicKey: Data,
        txType: TransactionType = .standard
    ) -> Transaction {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let id = calculateTransactionId(
            currency: currency,
            inputs: inputs,
            outputs: outputs,
            fee: fee,
            timestamp: timestamp,
            senderPublicKey: senderPublicKey
        )

        return Transaction(
            id: id,
            version: 2,
            currency: currency,
            inputs: inputs,
            outputs: outputs,
            fee: fee,
            timestamp: timestamp,
            memo: memo,
            senderPublicKey: senderPublicKey,
            signature: nil,
            confirmations: 0,
            txType: txType
        )
    }

    /// Calculate transaction ID (SHA-256 hash)
    static func calculateTransactionId(
        currency: String = "MTOK",
        inputs: [TransactionInput],
        outputs: [TransactionOutput],
        fee: UInt64,
        timestamp: UInt64,
        senderPublicKey: Data
    ) -> String {
        var hasher = SHA256()

        // Hash version
        hasher.update(data: Data([2])) // version 2

        // Hash currency code
        hasher.update(data: Data(currency.utf8))

        // Hash inputs
        for input in inputs {
            hasher.update(data: Data(input.previousTxId.utf8))
            hasher.update(data: withUnsafeBytes(of: input.outputIndex.bigEndian) { Data($0) })
        }

        // Hash outputs
        for output in outputs {
            hasher.update(data: Data(output.address.utf8))
            hasher.update(data: withUnsafeBytes(of: output.amount.bigEndian) { Data($0) })
        }

        // Hash fee and timestamp
        hasher.update(data: withUnsafeBytes(of: fee.bigEndian) { Data($0) })
        hasher.update(data: withUnsafeBytes(of: timestamp.bigEndian) { Data($0) })

        // Hash sender public key
        hasher.update(data: senderPublicKey)

        let hash = hasher.finalize()
        return Data(hash).hexEncodedString()
    }

    /// Get data to sign (excluding signature field)
    func dataToSign() -> Data {
        var data = Data()

        // Add version
        data.append(version)

        // Add inputs (without signatures)
        for input in inputs {
            data.append(Data(input.previousTxId.utf8))
            data.append(withUnsafeBytes(of: input.outputIndex.bigEndian) { Data($0) })
        }

        // Add outputs
        for output in outputs {
            data.append(Data(output.address.utf8))
            data.append(withUnsafeBytes(of: output.amount.bigEndian) { Data($0) })
        }

        // Add fee and timestamp
        data.append(withUnsafeBytes(of: fee.bigEndian) { Data($0) })
        data.append(withUnsafeBytes(of: timestamp.bigEndian) { Data($0) })

        return data
    }

    /// Sign the transaction with a payment identity
    mutating func sign(with identity: PaymentIdentity) throws {
        let dataToSign = self.dataToSign()
        let hash = SHA256.hash(data: dataToSign)

        let signingKey = try identity.signingKey()
        let signature = try signingKey.signature(for: Data(hash))
        self.signature = signature.dataRepresentation

        // Also sign each input
        for i in 0..<inputs.count {
            let inputData = Data(inputs[i].previousTxId.utf8) +
                           withUnsafeBytes(of: inputs[i].outputIndex.bigEndian) { Data($0) } +
                           withUnsafeBytes(of: timestamp.bigEndian) { Data($0) }
            let inputHash = SHA256.hash(data: inputData)
            let inputSignature = try signingKey.signature(for: Data(inputHash))
            inputs[i].signature = inputSignature.dataRepresentation
        }
    }

    /// Verify the transaction signature
    func verifySignature() -> Bool {
        guard let signature = signature else {
            return false
        }

        do {
            let dataToSign = self.dataToSign()
            let hash = SHA256.hash(data: dataToSign)

            let publicKey = try P256K.Signing.PublicKey(dataRepresentation: senderPublicKey)
            let ecdsaSignature = try P256K.Signing.ECDSASignature(dataRepresentation: signature)

            return publicKey.isValidSignature(ecdsaSignature, for: Data(hash))
        } catch {
            return false
        }
    }

    /// Calculate total input amount (requires UTXO set for lookup)
    func totalInputAmount(utxoSet: [String: UTXO]) -> UInt64 {
        inputs.reduce(0) { sum, input in
            if let utxo = utxoSet[input.utxoReference] {
                return sum + utxo.output.amount
            }
            return sum
        }
    }

    /// Calculate total output amount
    func totalOutputAmount() -> UInt64 {
        outputs.reduce(0) { $0 + $1.amount }
    }

    /// Validate transaction basic rules
    func validate(utxoSet: [String: UTXO]) -> TransactionValidationResult {
        // Check signature
        guard verifySignature() else {
            return .invalid(reason: "Invalid transaction signature")
        }

        // Check currency code format
        guard Currency.isValidCode(currency) else {
            return .invalid(reason: "Invalid currency code: \(currency)")
        }

        // Check inputs exist and currency consistency
        for input in inputs {
            guard let utxo = utxoSet[input.utxoReference] else {
                return .invalid(reason: "Input UTXO not found: \(input.utxoReference)")
            }

            // Ensure all inputs are same currency (except atomic swaps)
            if txType != .atomicSwap && utxo.currency != currency {
                return .invalid(reason: "Currency mismatch: expected \(currency), found \(utxo.currency)")
            }
        }

        // Check amounts
        let inputAmount = totalInputAmount(utxoSet: utxoSet)
        let outputAmount = totalOutputAmount()

        // Genesis transactions don't need input validation
        if txType != .genesis {
            guard inputAmount >= outputAmount + fee else {
                return .invalid(reason: "Insufficient input amount")
            }
        }

        // Check timestamp is recent (within 1 hour)
        let currentTime = UInt64(Date().timeIntervalSince1970 * 1000)
        let oneHour: UInt64 = 3_600_000
        guard abs(Int64(timestamp) - Int64(currentTime)) < Int64(oneHour) else {
            return .invalid(reason: "Transaction timestamp out of range")
        }

        // Check for duplicate inputs
        let inputRefs = Set(inputs.map { $0.utxoReference })
        guard inputRefs.count == inputs.count else {
            return .invalid(reason: "Duplicate inputs detected")
        }

        return .valid
    }
}

// MARK: - Validation
enum TransactionValidationResult {
    case valid
    case invalid(reason: String)

    var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }
}

// MARK: - Transaction Type
enum TransactionType: String, Codable {
    case standard           // Normal transaction
    case genesis           // Initial distribution
    case atomicSwap        // Cross-currency atomic swap
    case htlc              // Hashed Timelock Contract
}

// MARK: - Genesis Transaction
extension Transaction {
    /// Create a genesis transaction (initial token distribution)
    static func genesis(
        currency: String = "MTOK",
        recipients: [(address: String, amount: UInt64)],
        senderIdentity: PaymentIdentity
    ) throws -> Transaction {
        let outputs = recipients.map { TransactionOutput(address: $0.address, amount: $0.amount) }

        var tx = Transaction.create(
            currency: currency,
            inputs: [], // No inputs for genesis
            outputs: outputs,
            fee: 0,
            memo: "Genesis transaction - Initial \(currency) distribution",
            senderPublicKey: senderIdentity.publicKey,
            txType: .genesis
        )

        try tx.sign(with: senderIdentity)
        return tx
    }
}
