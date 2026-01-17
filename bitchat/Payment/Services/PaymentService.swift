import Foundation
import Combine
import BitLogger

/// Manages MeshPay payment protocol, transaction validation, and ledger
@MainActor
class PaymentService: ObservableObject {
    // MARK: - Published Properties

    /// Transaction history (confirmed transactions)
    @Published private(set) var transactionHistory: [Transaction] = []

    /// Mempool (pending transactions awaiting confirmation)
    @Published private(set) var mempool: [String: Transaction] = [:]

    /// Detected conflicts (double-spend attempts)
    @Published private(set) var conflicts: [TransactionConflict] = []

    /// Received payment requests
    @Published private(set) var paymentRequests: [PaymentRequest] = []

    // MARK: - Dependencies

    private let walletManager: WalletManager
    private weak var transportDelegate: PaymentTransportDelegate?

    // MARK: - Private Properties

    /// Seen transaction IDs for deduplication
    private var seenTransactions: Set<String> = []

    /// Transaction DAG for conflict resolution
    private var transactionGraph: TransactionGraph = TransactionGraph()

    /// Confirmation threshold (number of hops for finality)
    private let confirmationThreshold: UInt32 = 6

    /// Trust scores for peers (for conflict voting)
    private var peerTrustScores: [String: Double] = [:]

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(walletManager: WalletManager) {
        self.walletManager = walletManager
        loadTransactionHistory()
    }

    func setTransportDelegate(_ delegate: PaymentTransportDelegate) {
        self.transportDelegate = delegate
    }

    // MARK: - Transaction Reception

    /// Handle received transaction from mesh
    func handleReceivedTransaction(_ transaction: Transaction, from peerID: PeerID) {
        // Check if already seen
        guard !seenTransactions.contains(transaction.id) else {
            SecureLogger.info("📦 Ignoring duplicate transaction: \(transaction.id.prefix(8))", category: .session)
            return
        }

        SecureLogger.info("📥 Received transaction: \(transaction.id.prefix(8)) from \(peerID.id.prefix(8))", category: .session)

        // Mark as seen
        seenTransactions.insert(transaction.id)

        // Validate transaction
        let validationResult = transaction.validate(utxoSet: walletManager.utxoSet.utxos)

        switch validationResult {
        case .valid:
            // Check for double-spend
            if let conflict = detectDoubleSpend(transaction) {
                SecureLogger.warning("⚠️ Double-spend detected: \(transaction.id.prefix(8))", category: .session)
                handleConflict(conflict)
            } else {
                // Add to mempool
                mempool[transaction.id] = transaction
                walletManager.addPendingTransaction(transaction)

                // Propagate to mesh (gossip)
                propagateTransaction(transaction)

                // Check if this transaction is for us
                if isTransactionForCurrentWallet(transaction) {
                    SecureLogger.info("💰 Received payment: \(transaction.totalOutputAmount()) units", category: .session)
                    notifyPaymentReceived(transaction)
                }
            }

        case .invalid(let reason):
            SecureLogger.error("❌ Invalid transaction \(transaction.id.prefix(8)): \(reason)", category: .session)
            // Optionally notify peers about invalid transaction
        }
    }

    /// Check if transaction involves current wallet
    private func isTransactionForCurrentWallet(_ transaction: Transaction) -> Bool {
        guard let wallet = walletManager.currentWallet else { return false }
        let address = wallet.identity.address
        return transaction.outputs.contains { $0.address == address }
    }

    /// Notify about received payment
    private func notifyPaymentReceived(_ transaction: Transaction) {
        // This would trigger a notification or UI update
        // Implementation depends on UI framework
    }

    // MARK: - Transaction Sending

    /// Send payment to recipient
    func sendPayment(
        to recipientAddress: String,
        amount: UInt64,
        fee: UInt64 = 1000,
        memo: String? = nil
    ) async throws -> Transaction {
        // Validate address
        guard PaymentIdentity.isValidAddress(recipientAddress) else {
            throw PaymentError.invalidAddress
        }

        // Create transaction
        let transaction = try walletManager.createPayment(
            to: recipientAddress,
            amount: amount,
            fee: fee,
            memo: memo
        )

        // Add to mempool and pending transactions
        mempool[transaction.id] = transaction
        walletManager.addPendingTransaction(transaction)

        // Broadcast to mesh
        broadcastTransaction(transaction)

        SecureLogger.info("📤 Sent payment: \(amount) units to \(recipientAddress.prefix(12))...", category: .session)

        return transaction
    }

    /// Broadcast transaction to mesh network
    private func broadcastTransaction(_ transaction: Transaction) {
        guard let delegate = transportDelegate else {
            SecureLogger.error("❌ No transport delegate set", category: .session)
            return
        }

        delegate.broadcastTransaction(transaction)
    }

    /// Propagate transaction (rebroadcast with incremented hop count)
    private func propagateTransaction(_ transaction: Transaction) {
        guard let delegate = transportDelegate else { return }

        // Only propagate if hop count is reasonable
        if transaction.confirmations < 10 {
            delegate.broadcastTransaction(transaction)
        }
    }

    // MARK: - Transaction Confirmation

    /// Confirm a transaction (called when it reaches confirmation threshold)
    func confirmTransaction(_ transactionId: String, height: UInt32) {
        guard let transaction = mempool.removeValue(forKey: transactionId) else {
            return
        }

        // Add to history
        transactionHistory.append(transaction)
        walletManager.confirmTransaction(transactionId, height: height)

        // Add to graph
        transactionGraph.addTransaction(transaction)

        SecureLogger.info("✅ Transaction confirmed: \(transactionId.prefix(8))", category: .session)
        saveTransactionHistory()
    }

    /// Update transaction confirmations (called as it propagates)
    func updateConfirmations(_ transactionId: String, confirmations: UInt32) {
        if var transaction = mempool[transactionId] {
            transaction.confirmations = confirmations
            mempool[transactionId] = transaction

            // Auto-confirm if threshold reached
            if confirmations >= confirmationThreshold {
                confirmTransaction(transactionId, height: confirmations)
            }
        }
    }

    // MARK: - Double-Spend Detection

    /// Detect double-spend (same UTXO used in multiple transactions)
    private func detectDoubleSpend(_ newTransaction: Transaction) -> TransactionConflict? {
        let newInputRefs = Set(newTransaction.inputs.map { $0.utxoReference })

        // Check against mempool
        for (_, existingTx) in mempool {
            let existingInputRefs = Set(existingTx.inputs.map { $0.utxoReference })
            let commonInputs = newInputRefs.intersection(existingInputRefs)

            if !commonInputs.isEmpty {
                return TransactionConflict(
                    conflictingTransactions: [existingTx.id, newTransaction.id],
                    commonInputs: Array(commonInputs),
                    detectedAt: Date()
                )
            }
        }

        // Check against confirmed transactions
        for transaction in transactionHistory {
            let existingInputRefs = Set(transaction.inputs.map { $0.utxoReference })
            let commonInputs = newInputRefs.intersection(existingInputRefs)

            if !commonInputs.isEmpty {
                return TransactionConflict(
                    conflictingTransactions: [transaction.id, newTransaction.id],
                    commonInputs: Array(commonInputs),
                    detectedAt: Date()
                )
            }
        }

        return nil
    }

    /// Handle detected conflict
    private func handleConflict(_ conflict: TransactionConflict) {
        conflicts.append(conflict)

        // Initiate voting round
        initiateConflictVoting(conflict)
    }

    /// Initiate conflict voting
    private func initiateConflictVoting(_ conflict: TransactionConflict) {
        // In a real implementation, this would broadcast a vote request
        // and collect votes from trusted peers

        // For now, implement simple tie-breaking: keep the transaction with earlier timestamp
        guard conflict.conflictingTransactions.count >= 2 else { return }

        let tx1Id = conflict.conflictingTransactions[0]
        let tx2Id = conflict.conflictingTransactions[1]

        let tx1 = mempool[tx1Id]
        let tx2 = mempool[tx2Id]

        // Keep the one with earlier timestamp
        if let t1 = tx1, let t2 = tx2 {
            let keepId = t1.timestamp < t2.timestamp ? tx1Id : tx2Id
            let rejectId = keepId == tx1Id ? tx2Id : tx1Id

            resolveConflict(conflict, keepTransaction: keepId, rejectTransaction: rejectId)
        }
    }

    /// Resolve conflict by keeping one transaction and rejecting others
    private func resolveConflict(_ conflict: TransactionConflict, keepTransaction: String, rejectTransaction: String) {
        // Remove rejected transaction from mempool
        if let rejectedTx = mempool.removeValue(forKey: rejectTransaction) {
            walletManager.removePendingTransaction(rejectedTx.id)
            SecureLogger.info("🗑️ Rejected transaction: \(rejectTransaction.prefix(8))", category: .session)
        }

        // Remove conflict from list
        conflicts.removeAll { $0.id == conflict.id }

        SecureLogger.info("✅ Conflict resolved, keeping: \(keepTransaction.prefix(8))", category: .session)
    }

    // MARK: - Balance Queries

    /// Query balance from mesh peers
    func queryBalanceFromPeers(_ address: String) {
        guard let delegate = transportDelegate else { return }
        delegate.queryBalance(address)
    }

    /// Handle balance query from peer
    func handleBalanceQuery(from peerID: PeerID, address: String, queryId: String) {
        let balance = walletManager.getBalance(for: address)

        guard let delegate = transportDelegate else { return }
        delegate.respondToBalanceQuery(
            peerID: peerID,
            queryId: queryId,
            balance: balance.confirmed,
            utxoCount: balance.utxoCount
        )
    }

    /// Handle balance response from peer
    func handleBalanceResponse(from peerID: PeerID, balance: UInt64, queryId: String) {
        SecureLogger.info("💵 Balance from \(peerID.id.prefix(8)): \(balance) units", category: .session)
        // Could aggregate responses from multiple peers for consensus
    }

    // MARK: - Payment Requests

    /// Create payment request
    func createPaymentRequest(
        amount: UInt64,
        label: String? = nil,
        message: String? = nil
    ) throws -> PaymentRequest {
        guard let wallet = walletManager.currentWallet else {
            throw PaymentError.noWalletSelected
        }

        let request = PaymentRequest(
            address: wallet.identity.address,
            amount: amount,
            label: label,
            message: message
        )

        paymentRequests.append(request)
        return request
    }

    /// Handle received payment request
    func handlePaymentRequest(_ request: PaymentRequest, from peerID: PeerID) {
        paymentRequests.append(request)
        SecureLogger.info("📨 Payment request: \(request.amount) units from \(request.address.prefix(12))...", category: .session)
    }

    // MARK: - Storage

    private func loadTransactionHistory() {
        // Load from UserDefaults or persistent storage
        if let data = UserDefaults.standard.data(forKey: "meshpay.transaction_history"),
           let history = try? JSONDecoder().decode([Transaction].self, from: data) {
            transactionHistory = history
        }
    }

    private func saveTransactionHistory() {
        if let data = try? JSONEncoder().encode(transactionHistory) {
            UserDefaults.standard.set(data, forKey: "meshpay.transaction_history")
        }
    }

    // MARK: - Cleanup

    /// Clear old transactions from mempool
    func cleanupMempool() {
        let now = Date().timeIntervalSince1970 * 1000
        let maxAge: UInt64 = 3600_000 // 1 hour

        mempool = mempool.filter { _, tx in
            now - Double(tx.timestamp) < Double(maxAge)
        }
    }
}

// MARK: - Supporting Types

/// Transaction conflict (double-spend)
struct TransactionConflict: Identifiable {
    let id = UUID()
    let conflictingTransactions: [String]
    let commonInputs: [String]
    let detectedAt: Date
}

/// Transaction graph for DAG-based ordering
class TransactionGraph {
    private var transactions: [String: Transaction] = [:]
    private var edges: [String: Set<String>] = [:] // tx -> dependencies

    func addTransaction(_ transaction: Transaction) {
        transactions[transaction.id] = transaction

        // Add edges to input transactions
        let dependencies = Set(transaction.inputs.map { $0.previousTxId })
        edges[transaction.id] = dependencies
    }

    func getTransaction(_ id: String) -> Transaction? {
        transactions[id]
    }

    func getDependencies(_ id: String) -> Set<String> {
        edges[id] ?? []
    }
}

// MARK: - Transport Delegate Protocol

protocol PaymentTransportDelegate: AnyObject {
    func broadcastTransaction(_ transaction: Transaction)
    func queryBalance(_ address: String)
    func respondToBalanceQuery(peerID: PeerID, queryId: String, balance: UInt64, utxoCount: Int)
}

// MARK: - Errors

enum PaymentError: LocalizedError {
    case invalidAddress
    case insufficientFunds
    case transactionFailed
    case noWalletSelected

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid payment address"
        case .insufficientFunds:
            return "Insufficient funds"
        case .transactionFailed:
            return "Transaction failed"
        case .noWalletSelected:
            return "No wallet selected"
        }
    }
}
