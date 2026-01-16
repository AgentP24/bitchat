import Foundation
import Combine
import BitLogger

/// Manages funding sources and balance top-ups when online
@MainActor
class FundingManager: ObservableObject {
    // MARK: - Published Properties

    /// Connected funding sources (bank accounts, cards, etc.)
    @Published private(set) var fundingSources: [FundingSource] = []

    /// Pending deposits waiting for network sync
    @Published private(set) var pendingDeposits: [Deposit] = []

    /// Transaction history
    @Published private(set) var depositHistory: [Deposit] = []

    /// Current network status
    @Published var isOnline: Bool = false

    /// Last sync timestamp
    @Published private(set) var lastSyncTime: Date?

    // MARK: - Dependencies

    private weak var walletManager: WalletManager?
    private let currencyRegistry: CurrencyRegistry
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(walletManager: WalletManager? = nil, currencyRegistry: CurrencyRegistry) {
        self.walletManager = walletManager
        self.currencyRegistry = currencyRegistry

        // Monitor network connectivity
        setupNetworkMonitoring()

        // Load saved data
        loadFundingSources()
        loadPendingDeposits()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        // Monitor network reachability
        $isOnline
            .removeDuplicates()
            .sink { [weak self] online in
                if online {
                    self?.handleOnlineStatus()
                }
            }
            .store(in: &cancellables)
    }

    /// Called when device comes online
    private func handleOnlineStatus() {
        SecureLogger.info("🌐 Device is online, syncing balances...", category: .session)

        Task {
            await syncPendingDeposits()
            await refreshBalances()
        }
    }

    // MARK: - Funding Source Management

    /// Add a new funding source (bank account, credit card, etc.)
    func addFundingSource(
        type: FundingSourceType,
        name: String,
        accountNumber: String,
        routingInfo: String? = nil
    ) throws -> FundingSource {
        let source = FundingSource(
            id: UUID(),
            type: type,
            name: name,
            accountNumber: accountNumber,
            routingInfo: routingInfo,
            isVerified: false,
            addedAt: Date()
        )

        fundingSources.append(source)
        saveFundingSources()

        SecureLogger.info("➕ Added funding source: \(name)", category: .session)
        return source
    }

    /// Remove funding source
    func removeFundingSource(_ sourceId: UUID) {
        fundingSources.removeAll { $0.id == sourceId }
        saveFundingSources()
    }

    /// Verify funding source (would involve micro-deposits or external API)
    func verifyFundingSource(_ sourceId: UUID) async throws {
        guard let index = fundingSources.firstIndex(where: { $0.id == sourceId }) else {
            throw FundingError.sourceNotFound
        }

        // In production: Initiate verification process
        // - Send micro-deposits
        // - User confirms amounts
        // - Or use instant verification via Plaid/Stripe

        // Mock verification delay
        try await Task.sleep(nanoseconds: 2_000_000_000)

        fundingSources[index].isVerified = true
        saveFundingSources()

        SecureLogger.info("✅ Funding source verified", category: .session)
    }

    // MARK: - Deposits

    /// Initiate a deposit from funding source to wallet
    func initiateDeposit(
        from sourceId: UUID,
        amount: Double,
        currency: String,
        toAddress: String
    ) async throws -> Deposit {
        guard let source = fundingSources.first(where: { $0.id == sourceId }) else {
            throw FundingError.sourceNotFound
        }

        guard source.isVerified else {
            throw FundingError.sourceNotVerified
        }

        guard let currencyInfo = currencyRegistry.get(currency) else {
            throw FundingError.unsupportedCurrency
        }

        // Convert to base units
        let amountInUnits = currencyInfo.parseAmount(String(amount)) ?? 0

        let deposit = Deposit(
            id: UUID(),
            sourceId: sourceId,
            sourceName: source.name,
            amount: amountInUnits,
            currency: currency,
            destinationAddress: toAddress,
            status: isOnline ? .processing : .pending,
            initiatedAt: Date(),
            completedAt: nil
        )

        if isOnline {
            // Process immediately if online
            try await processDeposit(deposit)
        } else {
            // Queue for later if offline
            pendingDeposits.append(deposit)
            savePendingDeposits()
            SecureLogger.info("📥 Deposit queued for sync: \(deposit.id)", category: .session)
        }

        depositHistory.append(deposit)
        saveDepositHistory()

        return deposit
    }

    /// Process a deposit (when online)
    private func processDeposit(_ deposit: Deposit) async throws {
        guard isOnline else {
            throw FundingError.offline
        }

        SecureLogger.info("💳 Processing deposit: \(deposit.amount) \(deposit.currency)", category: .session)

        // In production, this would:
        // 1. Call banking API to initiate ACH transfer
        // 2. Wait for bank confirmation
        // 3. Mint equivalent tokens on mesh
        // 4. Send to user's address

        // Mock processing delay
        try await Task.sleep(nanoseconds: 3_000_000_000)

        // Update deposit status
        if let index = pendingDeposits.firstIndex(where: { $0.id == deposit.id }) {
            pendingDeposits[index].status = .completed
            pendingDeposits[index].completedAt = Date()

            // Create genesis transaction to credit wallet
            try await creditWallet(deposit)

            // Remove from pending
            pendingDeposits.remove(at: index)
            savePendingDeposits()
        }

        SecureLogger.info("✅ Deposit completed: \(deposit.id)", category: .session)
    }

    /// Credit wallet with deposited funds
    private func creditWallet(_ deposit: Deposit) async throws {
        guard let walletManager = walletManager else {
            throw FundingError.walletManagerNotAvailable
        }

        // Create a genesis transaction to credit the wallet
        let wallet = try walletManager.wallets.first {
            $0.identity.address == deposit.destinationAddress
        } ?? walletManager.currentWallet

        guard let wallet = wallet else {
            throw FundingError.noWalletAvailable
        }

        let genesisTx = try Transaction.genesis(
            currency: deposit.currency,
            recipients: [(address: wallet.identity.address, amount: deposit.amount)],
            senderIdentity: wallet.identity
        )

        // Add to wallet
        walletManager.addTransaction(genesisTx, height: 0)

        SecureLogger.info("💰 Wallet credited: \(deposit.amount) \(deposit.currency)", category: .session)
    }

    /// Sync pending deposits when online
    private func syncPendingDeposits() async {
        guard isOnline, !pendingDeposits.isEmpty else {
            return
        }

        SecureLogger.info("🔄 Syncing \(pendingDeposits.count) pending deposits...", category: .session)

        for deposit in pendingDeposits {
            do {
                try await processDeposit(deposit)
            } catch {
                SecureLogger.error("❌ Failed to process deposit \(deposit.id): \(error)", category: .session)
            }
        }

        lastSyncTime = Date()
    }

    // MARK: - Balance Refresh

    /// Refresh balances from external sources
    private func refreshBalances() async {
        guard isOnline else { return }

        SecureLogger.info("🔄 Refreshing balances from funding sources...", category: .session)

        // In production: Query banking APIs for current balances
        // Update local cache

        for var source in fundingSources {
            // Mock balance query
            source.cachedBalance = Double.random(in: 100...10000)
        }

        saveFundingSources()
    }

    // MARK: - Exchange

    /// Convert fiat to crypto (on-ramp)
    func buyTokens(
        fromSource sourceId: UUID,
        fiatAmount: Double,
        fiatCurrency: String,
        toCurrency: String
    ) async throws -> Deposit {
        guard let exchangeRate = currencyRegistry.getRate(base: fiatCurrency, quote: toCurrency) else {
            throw FundingError.exchangeRateUnavailable
        }

        let tokenAmount = fiatAmount * exchangeRate

        guard let wallet = walletManager?.currentWallet else {
            throw FundingError.noWalletAvailable
        }

        return try await initiateDeposit(
            from: sourceId,
            amount: tokenAmount,
            currency: toCurrency,
            toAddress: wallet.identity.address
        )
    }

    /// Convert crypto to fiat (off-ramp)
    func sellTokens(
        amount: UInt64,
        currency: String,
        toSource sourceId: UUID
    ) async throws {
        // In production:
        // 1. Burn tokens from mesh
        // 2. Initiate bank transfer
        // 3. Wait for confirmation

        SecureLogger.info("💱 Selling \(amount) \(currency)", category: .session)
        throw FundingError.notImplemented
    }

    // MARK: - Persistence

    private func loadFundingSources() {
        if let data = UserDefaults.standard.data(forKey: "meshpay.funding_sources"),
           let sources = try? JSONDecoder().decode([FundingSource].self, from: data) {
            fundingSources = sources
        }
    }

    private func saveFundingSources() {
        if let data = try? JSONEncoder().encode(fundingSources) {
            UserDefaults.standard.set(data, forKey: "meshpay.funding_sources")
        }
    }

    private func loadPendingDeposits() {
        if let data = UserDefaults.standard.data(forKey: "meshpay.pending_deposits"),
           let deposits = try? JSONDecoder().decode([Deposit].self, from: data) {
            pendingDeposits = deposits
        }
    }

    private func savePendingDeposits() {
        if let data = try? JSONEncoder().encode(pendingDeposits) {
            UserDefaults.standard.set(data, forKey: "meshpay.pending_deposits")
        }
    }

    private func saveDepositHistory() {
        if let data = try? JSONEncoder().encode(depositHistory) {
            UserDefaults.standard.set(data, forKey: "meshpay.deposit_history")
        }
    }
}

// MARK: - Supporting Types

/// Funding source (bank account, credit card, etc.)
struct FundingSource: Codable, Identifiable {
    let id: UUID
    let type: FundingSourceType
    let name: String
    let accountNumber: String  // Masked in UI
    let routingInfo: String?
    var isVerified: Bool
    let addedAt: Date
    var cachedBalance: Double? // Last known balance
}

/// Type of funding source
enum FundingSourceType: String, Codable {
    case bankAccount = "Bank Account"
    case creditCard = "Credit Card"
    case debitCard = "Debit Card"
    case paypal = "PayPal"
    case venmo = "Venmo"
    case cashApp = "Cash App"
}

/// Deposit transaction
struct Deposit: Codable, Identifiable {
    let id: UUID
    let sourceId: UUID
    let sourceName: String
    let amount: UInt64
    let currency: String
    let destinationAddress: String
    var status: DepositStatus
    let initiatedAt: Date
    var completedAt: Date?

    var amountDisplay: String {
        let divisor = pow(10.0, 8.0) // Assume 8 decimals
        let value = Double(amount) / divisor
        return String(format: "%.8f %@", value, currency)
    }
}

/// Deposit status
enum DepositStatus: String, Codable {
    case pending      // Waiting for network
    case processing   // Being processed
    case completed    // Successfully completed
    case failed       // Failed
    case cancelled    // User cancelled
}

/// Funding errors
enum FundingError: LocalizedError {
    case sourceNotFound
    case sourceNotVerified
    case unsupportedCurrency
    case offline
    case walletManagerNotAvailable
    case noWalletAvailable
    case exchangeRateUnavailable
    case insufficientFunds
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "Funding source not found"
        case .sourceNotVerified:
            return "Funding source not verified"
        case .unsupportedCurrency:
            return "Currency not supported"
        case .offline:
            return "Device is offline"
        case .walletManagerNotAvailable:
            return "Wallet manager not available"
        case .noWalletAvailable:
            return "No wallet available"
        case .exchangeRateUnavailable:
            return "Exchange rate not available"
        case .insufficientFunds:
            return "Insufficient funds"
        case .notImplemented:
            return "Feature not yet implemented"
        }
    }
}
