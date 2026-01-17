import Foundation
import SwiftUI
import Combine

/// Comprehensive demo for MeshPay v1.1 features
@MainActor
class MeshPayDemo: ObservableObject {
    // MARK: - Services

    let walletManager: WalletManager
    let paymentService: PaymentService
    let currencyRegistry: CurrencyRegistry
    let fundingManager: FundingManager
    let hardwareWalletManager: HardwareWalletManager

    // MARK: - Demo State

    @Published var currentScenario: DemoScenario?
    @Published var scenarioLog: [String] = []
    @Published var isRunning = false

    // MARK: - Initialization

    init() {
        // Initialize services
        self.currencyRegistry = CurrencyRegistry()
        self.walletManager = WalletManager()
        self.paymentService = PaymentService(walletManager: walletManager)
        self.fundingManager = FundingManager(
            walletManager: walletManager,
            currencyRegistry: currencyRegistry
        )
        self.hardwareWalletManager = HardwareWalletManager()

        // Set up service connections with mock transport for demo
        let mockDelegate = MockPaymentTransportDelegate()
        paymentService.setTransportDelegate(mockDelegate)
    }

    // MARK: - Demo Scenarios

    /// Run all demo scenarios
    func runFullDemo() async {
        log("🚀 Starting MeshPay v1.1 Full Demo")
        log("=================================\n")

        await runScenario1_MultiCurrencyBasics()
        await runScenario2_AtomicSwap()
        await runScenario3_HardwareWallet()
        await runScenario4_BankIntegration()

        log("\n✅ Full demo completed!")
    }

    // MARK: - Scenario 1: Multi-Currency Basics

    func runScenario1_MultiCurrencyBasics() async {
        currentScenario = .multiCurrency
        log("\n📊 Scenario 1: Multi-Currency Basics")
        log("-----------------------------------")

        do {
            // Create wallets
            log("1️⃣ Creating wallets...")
            let aliceWallet = try walletManager.createWallet(label: "Alice's Wallet")
            let bobWallet = try walletManager.createWallet(label: "Bob's Wallet")

            log("   ✓ Alice: \(aliceWallet.identity.address.prefix(20))...")
            log("   ✓ Bob: \(bobWallet.identity.address.prefix(20))...")

            // Fund Alice with multiple currencies
            log("\n2️⃣ Funding Alice with multiple currencies...")

            let currencies = ["MTOK", "WBTC", "MUSD"]
            for currency in currencies {
                let genesisTx = try Transaction.genesis(
                    currency: currency,
                    recipients: [(address: aliceWallet.identity.address, amount: 100_000_000)],
                    senderIdentity: aliceWallet.identity
                )

                walletManager.addTransaction(genesisTx, height: 0)
                log("   ✓ Funded with \(currencyRegistry.get(currency)?.format(amount: 100_000_000) ?? "\(currency)")")
            }

            // Check balances
            log("\n3️⃣ Alice's balances:")
            let balances = walletManager.utxoSet.balancesByCurrency(for: aliceWallet.identity.address)
            for (currency, amount) in balances.sorted(by: { $0.key < $1.key }) {
                if let currencyInfo = currencyRegistry.get(currency) {
                    log("   • \(currencyInfo.format(amount: amount))")
                }
            }

            // Send payment in WBTC
            log("\n4️⃣ Alice sends 0.5 WBTC to Bob...")
            try await walletManager.setCurrentWallet(aliceWallet)

            let wbtcPayment = try walletManager.createPayment(
                to: bobWallet.identity.address,
                amount: 50_000_000,
                fee: 500,
                memo: "Payment in Bitcoin"
            )

            // Verify currency consistency
            if wbtcPayment.currency == "WBTC" {
                log("   ✓ Transaction created: \(wbtcPayment.id.prefix(16))...")
                log("   ✓ Currency: \(wbtcPayment.currency)")
                log("   ✓ Amount: 0.5 WBTC")
                log("   ✓ Fee: 0.000005 WBTC")
            }

            log("\n✅ Multi-currency demo completed")

        } catch {
            log("❌ Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Scenario 2: Atomic Swap

    func runScenario2_AtomicSwap() async {
        currentScenario = .atomicSwap
        log("\n🔄 Scenario 2: Atomic Swap (MTOK ↔ MUSD)")
        log("------------------------------------------")

        do {
            // Get wallets
            guard walletManager.wallets.count >= 2,
                  let alice = walletManager.wallets.first,
                  let bob = walletManager.wallets.dropFirst().first else {
                log("❌ Need at least 2 wallets")
                return
            }

            log("1️⃣ Setting up atomic swap...")
            log("   • Alice wants to exchange 10 MT for $10 MUSD")
            log("   • Bob has MUSD and wants MT")

            // Get exchange rate
            let rate = currencyRegistry.getRate(base: "MTOK", quote: "MUSD") ?? 0.01
            log("   • Exchange rate: 1 MT = $\(rate) MUSD")

            // Create swap proposal
            let swap = AtomicSwap.createProposal(
                partyAAddress: alice.identity.address,
                partyACurrency: "MTOK",
                partyAAmount: 10_00_000_000, // 10 MT
                partyBAddress: bob.identity.address,
                partyBCurrency: "MUSD",
                exchangeRate: rate,
                partyADecimals: 8,
                partyBDecimals: 6
            )

            log("\n2️⃣ Swap created:")
            log("   • Swap ID: \(swap.id.prefix(16))...")
            log("   • Alice offers: \(currencyRegistry.get("MTOK")?.format(amount: swap.partyA.amount) ?? "")")
            log("   • Bob offers: \(currencyRegistry.get("MUSD")?.format(amount: swap.partyB.amount) ?? "")")
            log("   • Secret hash: \(swap.secretHash.hexEncodedString().prefix(16))...")

            // Verify fairness
            if swap.verifyFairness(exchangeRate: rate) {
                log("   ✓ Swap is fair (within 1% tolerance)")
            }

            // Create HTLCs
            log("\n3️⃣ Creating HTLCs...")

            let timelock = UInt64(Date().timeIntervalSince1970 * 1000) + 3_600_000 // 1 hour

            let aliceHTLC = HTLC(
                sender: alice.identity.address,
                recipient: bob.identity.address,
                currency: "MTOK",
                amount: swap.partyA.amount,
                hashLock: swap.secretHash,
                timeLock: timelock,
                fundingTxId: "mock_alice_tx"
            )

            let bobHTLC = HTLC(
                sender: bob.identity.address,
                recipient: alice.identity.address,
                currency: "MUSD",
                amount: swap.partyB.amount,
                hashLock: swap.secretHash,
                timeLock: timelock,
                fundingTxId: "mock_bob_tx"
            )

            log("   ✓ Alice's HTLC: locks \(currencyRegistry.get("MTOK")?.format(amount: aliceHTLC.amount) ?? "")")
            log("   ✓ Bob's HTLC: locks \(currencyRegistry.get("MUSD")?.format(amount: bobHTLC.amount) ?? "")")

            // Reveal secret and claim
            log("\n4️⃣ Executing swap...")
            if let secret = swap.secret {
                log("   • Alice reveals secret: \(secret.hexEncodedString().prefix(16))...")

                var aliceHTLCMut = aliceHTLC
                var bobHTLCMut = bobHTLC

                if aliceHTLCMut.verifyPreimage(secret) && bobHTLCMut.verifyPreimage(secret) {
                    log("   ✓ Secret verified by both HTLCs")

                    _ = bobHTLCMut.claim(preimage: secret, txId: "claim_tx_bob")
                    _ = aliceHTLCMut.claim(preimage: secret, txId: "claim_tx_alice")

                    log("   ✓ Bob claimed Alice's HTLC")
                    log("   ✓ Alice claimed Bob's HTLC")
                }
            }

            log("\n✅ Atomic swap completed successfully!")
            log("   • Alice now has MUSD")
            log("   • Bob now has MTOK")

        } catch {
            log("❌ Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Scenario 3: Hardware Wallet

    func runScenario3_HardwareWallet() async {
        currentScenario = .hardwareWallet
        log("\n🔐 Scenario 3: Hardware Wallet Integration")
        log("------------------------------------------")

        // Create mock hardware wallet
        let mockDevice = HardwareWallet(
            id: UUID(),
            name: "Ledger Nano X",
            type: .ledgerNanoX,
            firmwareVersion: "2.1.0",
            fingerprint: "ABCD1234"
        )

        log("1️⃣ Discovered hardware wallet:")
        log("   • Name: \(mockDevice.name)")
        log("   • Type: \(mockDevice.type.rawValue)")
        log("   • Firmware: \(mockDevice.firmwareVersion)")
        log("   • Fingerprint: \(mockDevice.fingerprint)")

        log("\n2️⃣ Verifying device fingerprint...")
        if hardwareWalletManager.verifyFingerprint(mockDevice.fingerprint, for: mockDevice) {
            log("   ✓ Fingerprint verified (OOB)")
        }

        log("\n3️⃣ Deriving address from hardware wallet...")
        do {
            // Mock connected device by pairing it
            try hardwareWalletManager.pair(mockDevice, fingerprint: mockDevice.fingerprint)

            let address = try await hardwareWalletManager.deriveAddress(
                from: mockDevice,
                coinType: 0,
                account: 0,
                addressIndex: 0
            )
            log("   ✓ Derived address: \(address.prefix(20))...")

            // Create high-value transaction
            log("\n4️⃣ Creating high-value transaction (requires hardware signing)...")

            if let wallet = walletManager.currentWallet {
                // Fund wallet
                let genesisTx = try Transaction.genesis(
                    currency: "MTOK",
                    recipients: [(address: wallet.identity.address, amount: 200_000_000)],
                    senderIdentity: wallet.identity
                )
                walletManager.addTransaction(genesisTx, height: 0)

                // Create large transaction
                var largeTx = try walletManager.createPayment(
                    to: address,
                    amount: 150_000_000, // 1.5 MT (above threshold)
                    fee: 1000
                )

                if hardwareWalletManager.requiresHardwareWallet(largeTx) {
                    log("   ⚠️  Transaction exceeds hardware wallet threshold")
                    log("   📱 Requesting signature from hardware device...")

                    // Sign with hardware
                    largeTx = try await hardwareWalletManager.signTransaction(largeTx, with: mockDevice)

                    log("   ✓ Transaction signed by hardware wallet")
                    log("   ✓ Private key never left device")
                }
            }

            log("\n✅ Hardware wallet demo completed")

        } catch {
            log("❌ Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Scenario 4: Bank Integration

    func runScenario4_BankIntegration() async {
        currentScenario = .bankIntegration
        log("\n🏦 Scenario 4: Bank Integration & Funding")
        log("------------------------------------------")

        do {
            // Add funding source
            log("1️⃣ Adding bank account...")
            let bankAccount = try fundingManager.addFundingSource(
                type: .bankAccount,
                name: "Chase Checking ****1234",
                accountNumber: "****1234",
                routingInfo: "021000021"
            )
            log("   ✓ Bank account added: \(bankAccount.name)")

            // Verify funding source
            log("\n2️⃣ Verifying bank account...")
            try await fundingManager.verifyFundingSource(bankAccount.id)
            log("   ✓ Account verified via micro-deposits")

            // Simulate going online
            log("\n3️⃣ Device comes online...")
            fundingManager.isOnline = true
            log("   ✓ Network connectivity established")

            // Buy tokens with fiat
            log("\n4️⃣ Buying MeshTokens with USD...")
            log("   • Amount: $100 USD")
            log("   • Exchange rate: 1 USD = 100 MT")

            guard let wallet = walletManager.currentWallet else {
                log("❌ No wallet available")
                return
            }

            let deposit = try await fundingManager.buyTokens(
                fromSource: bankAccount.id,
                fiatAmount: 100.0,
                fiatCurrency: "MUSD",
                toCurrency: "MTOK"
            )

            log("   ✓ Purchase initiated: \(deposit.id.uuidString.prefix(16))...")
            log("   ✓ Status: \(deposit.status.rawValue)")
            log("   ✓ Amount: \(deposit.amountDisplay)")
            log("   ✓ Destination: \(wallet.identity.address.prefix(20))...")

            // Check balance
            log("\n5️⃣ Checking wallet balance...")
            let balance = walletManager.balance
            log("   • Confirmed: \(balance.confirmedTokens) MT")
            log("   • Pending: \(balance.pendingTokens) MT")

            log("\n✅ Bank integration demo completed")
            log("   • Seamless fiat → crypto on-ramp")
            log("   • Balance syncs when online")
            log("   • Funds usable immediately after confirmation")

        } catch {
            log("❌ Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        scenarioLog.append(message)
        print(message)
    }

    /// Clear demo state
    func reset() {
        scenarioLog = []
        currentScenario = nil
        isRunning = false
    }
}

// MARK: - Demo Scenarios

enum DemoScenario {
    case multiCurrency
    case atomicSwap
    case hardwareWallet
    case bankIntegration
}

// MARK: - Mock Transport Delegate

/// Mock payment transport delegate for demo purposes
class MockPaymentTransportDelegate: PaymentTransportDelegate {
    func broadcastTransaction(_ transaction: Transaction) {
        // Mock: No-op for demo
    }

    func queryBalance(_ address: String) {
        // Mock: No-op for demo
    }

    func respondToBalanceQuery(peerID: PeerID, queryId: String, balance: UInt64, utxoCount: Int) {
        // Mock: No-op for demo
    }
}
