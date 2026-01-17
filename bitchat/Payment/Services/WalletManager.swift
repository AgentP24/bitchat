import Foundation
import Combine

/// Manages MeshPay wallets, UTXOs, and balances
@MainActor
class WalletManager: ObservableObject {
    // MARK: - Published Properties

    /// Current active wallet
    @Published private(set) var currentWallet: Wallet?

    /// All managed wallets
    @Published private(set) var wallets: [Wallet] = []

    /// Current wallet balance
    @Published private(set) var balance: WalletBalance = .zero

    /// UTXO set for all addresses
    @Published private(set) var utxoSet: UTXOSet = UTXOSet()

    /// Pending transactions (not yet confirmed)
    @Published private(set) var pendingTransactions: [Transaction] = []

    // MARK: - Private Properties

    private let storage: WalletStorage
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(storage: WalletStorage = UserDefaultsWalletStorage()) {
        self.storage = storage
        loadWallets()
    }

    // MARK: - Wallet Management

    /// Create a new wallet
    func createWallet(label: String = "Default Wallet") throws -> Wallet {
        let wallet = try Wallet.generate(label: label)

        // Set as default if this is the first wallet
        var mutableWallet = wallet
        if wallets.isEmpty {
            mutableWallet.isDefault = true
            currentWallet = mutableWallet
        }

        wallets.append(mutableWallet)
        try storage.saveWallets(wallets)

        return mutableWallet
    }

    /// Import wallet from private key
    func importWallet(privateKey: Data, label: String) throws -> Wallet {
        let wallet = try Wallet.importFromPrivateKey(privateKey, label: label)
        wallets.append(wallet)
        try storage.saveWallets(wallets)
        return wallet
    }

    /// Set active wallet
    func setCurrentWallet(_ wallet: Wallet) throws {
        guard wallets.contains(where: { $0.id == wallet.id }) else {
            throw WalletError.walletNotFound
        }

        // Update default flag
        for i in 0..<wallets.count {
            wallets[i].isDefault = (wallets[i].id == wallet.id)
        }

        currentWallet = wallet
        try storage.saveWallets(wallets)
        updateBalance()
    }

    /// Delete wallet
    func deleteWallet(_ walletId: String) throws {
        guard let index = wallets.firstIndex(where: { $0.id == walletId }) else {
            throw WalletError.walletNotFound
        }

        _ = wallets.remove(at: index)

        // If deleted wallet was current, set another as current
        if currentWallet?.id == walletId {
            currentWallet = wallets.first
            if let newCurrent = currentWallet {
                try setCurrentWallet(newCurrent)
            }
        }

        try storage.saveWallets(wallets)
    }

    // MARK: - UTXO Management

    /// Update UTXO set with a new transaction
    func addTransaction(_ transaction: Transaction, height: UInt32 = 0) {
        utxoSet.applyTransaction(transaction, height: height)
        updateBalance()
        try? storage.saveUTXOs(utxoSet)
    }

    /// Remove transaction (e.g., in case of conflict)
    func removeTransaction(_ transaction: Transaction) {
        utxoSet.revertTransaction(transaction)
        updateBalance()
        try? storage.saveUTXOs(utxoSet)
    }

    /// Add pending transaction
    func addPendingTransaction(_ transaction: Transaction) {
        pendingTransactions.append(transaction)
        updateBalance()
    }

    /// Confirm pending transaction
    func confirmTransaction(_ transactionId: String, height: UInt32) {
        guard let index = pendingTransactions.firstIndex(where: { $0.id == transactionId }) else {
            return
        }

        let transaction = pendingTransactions.remove(at: index)
        addTransaction(transaction, height: height)
    }

    /// Remove pending transaction
    func removePendingTransaction(_ transactionId: String) {
        pendingTransactions.removeAll { $0.id == transactionId }
        updateBalance()
    }

    // MARK: - Balance Calculation

    /// Update current wallet balance
    private func updateBalance() {
        guard let wallet = currentWallet else {
            balance = .zero
            return
        }

        let address = wallet.identity.address

        // Calculate confirmed balance
        let confirmedAmount = utxoSet.balance(for: address)
        let utxoCount = utxoSet.unspent(for: address).count

        // Calculate pending balance
        let pendingAmount = pendingTransactions
            .filter { tx in
                tx.outputs.contains { $0.address == address }
            }
            .reduce(0 as UInt64) { sum, tx in
                let receivedAmount = tx.outputs
                    .filter { $0.address == address }
                    .reduce(0 as UInt64) { $0 + $1.amount }
                return sum + receivedAmount
            }

        balance = WalletBalance(
            confirmed: confirmedAmount,
            pending: pendingAmount,
            utxoCount: utxoCount
        )
    }

    /// Get balance for specific address
    func getBalance(for address: String) -> WalletBalance {
        let confirmedAmount = utxoSet.balance(for: address)
        let utxoCount = utxoSet.unspent(for: address).count

        let pendingAmount = pendingTransactions
            .filter { tx in
                tx.outputs.contains { $0.address == address }
            }
            .reduce(0) { sum, tx in
                let receivedAmount = tx.outputs
                    .filter { $0.address == address }
                    .reduce(0) { $0 + $1.amount }
                return sum + receivedAmount
            }

        return WalletBalance(
            confirmed: confirmedAmount,
            pending: pendingAmount,
            utxoCount: utxoCount
        )
    }

    // MARK: - Transaction Creation

    /// Create a payment transaction
    func createPayment(
        to recipientAddress: String,
        amount: UInt64,
        currency: String = "MTOK",
        fee: UInt64 = 1000, // Default 0.00001 MT
        memo: String? = nil
    ) throws -> Transaction {
        guard let wallet = currentWallet else {
            throw WalletError.noWalletSelected
        }

        let address = wallet.identity.address

        // Select UTXOs for payment (currency-specific)
        guard let selectedUtxos = utxoSet.selectForPayment(
            from: address,
            amount: amount + fee,
            currency: currency
        ) else {
            throw WalletError.insufficientFunds
        }

        // Create inputs from selected UTXOs
        let inputs = selectedUtxos.map { utxo in
            TransactionInput(
                previousTxId: utxo.transactionId,
                outputIndex: utxo.outputIndex
            )
        }

        // Calculate total input amount
        let totalInput = selectedUtxos.reduce(0) { $0 + $1.output.amount }

        // Create outputs
        var outputs = [TransactionOutput(address: recipientAddress, amount: amount)]

        // Add change output if needed
        let change = totalInput - amount - fee
        if change > 0 {
            outputs.append(TransactionOutput(address: address, amount: change))
        }

        // Create and sign transaction
        var transaction = Transaction.create(
            currency: currency,
            inputs: inputs,
            outputs: outputs,
            fee: fee,
            memo: memo,
            senderPublicKey: wallet.identity.publicKey
        )

        try transaction.sign(with: wallet.identity)

        return transaction
    }

    /// Create a genesis transaction (for testing or initial distribution)
    func createGenesis(
        currency: String = "MTOK",
        recipients: [(address: String, amount: UInt64)]
    ) throws -> Transaction {
        guard let wallet = currentWallet else {
            throw WalletError.noWalletSelected
        }

        return try Transaction.genesis(
            currency: currency,
            recipients: recipients,
            senderIdentity: wallet.identity
        )
    }

    /// Get balances for all currencies
    func getBalancesByCurrency(for wallet: Wallet) -> [String: WalletBalance] {
        let address = wallet.identity.address
        let balanceDict = utxoSet.balancesByCurrency(for: address)

        var result: [String: WalletBalance] = [:]
        for (currency, amount) in balanceDict {
            let utxoCount = utxoSet.unspent(for: address, currency: currency).count
            result[currency] = WalletBalance(confirmed: amount, pending: 0, utxoCount: utxoCount)
        }

        return result
    }

    // MARK: - Storage

    private func loadWallets() {
        do {
            wallets = try storage.loadWallets()
            currentWallet = wallets.first { $0.isDefault } ?? wallets.first
            utxoSet = try storage.loadUTXOs()
            updateBalance()
        } catch {
            // First run or error, create default wallet
            do {
                let wallet = try createWallet()
                currentWallet = wallet
            } catch {
                // Failed to create wallet
            }
        }
    }

    /// Clear all data (for testing)
    func clearAll() throws {
        wallets = []
        currentWallet = nil
        utxoSet = UTXOSet()
        pendingTransactions = []
        balance = .zero
        try storage.clearAll()
    }
}

// MARK: - Errors

enum WalletError: LocalizedError {
    case noWalletSelected
    case walletNotFound
    case insufficientFunds
    case invalidAddress
    case transactionCreationFailed

    var errorDescription: String? {
        switch self {
        case .noWalletSelected:
            return "No wallet selected"
        case .walletNotFound:
            return "Wallet not found"
        case .insufficientFunds:
            return "Insufficient funds"
        case .invalidAddress:
            return "Invalid payment address"
        case .transactionCreationFailed:
            return "Failed to create transaction"
        }
    }
}

// MARK: - Storage Protocol

protocol WalletStorage {
    func saveWallets(_ wallets: [Wallet]) throws
    func loadWallets() throws -> [Wallet]
    func saveUTXOs(_ utxoSet: UTXOSet) throws
    func loadUTXOs() throws -> UTXOSet
    func clearAll() throws
}

/// UserDefaults-based wallet storage
class UserDefaultsWalletStorage: WalletStorage {
    private let walletsKey = "meshpay.wallets"
    private let utxosKey = "meshpay.utxos"

    func saveWallets(_ wallets: [Wallet]) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(wallets)
        UserDefaults.standard.set(data, forKey: walletsKey)
    }

    func loadWallets() throws -> [Wallet] {
        guard let data = UserDefaults.standard.data(forKey: walletsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        return try decoder.decode([Wallet].self, from: data)
    }

    func saveUTXOs(_ utxoSet: UTXOSet) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(utxoSet)
        UserDefaults.standard.set(data, forKey: utxosKey)
    }

    func loadUTXOs() throws -> UTXOSet {
        guard let data = UserDefaults.standard.data(forKey: utxosKey) else {
            return UTXOSet()
        }
        let decoder = JSONDecoder()
        return try decoder.decode(UTXOSet.self, from: data)
    }

    func clearAll() throws {
        UserDefaults.standard.removeObject(forKey: walletsKey)
        UserDefaults.standard.removeObject(forKey: utxosKey)
    }
}
