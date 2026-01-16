import Foundation
import CryptoKit

/// Hashed Timelock Contract for atomic swaps
/// Enables trustless cross-currency exchanges using hash preimages and timelocks
struct HTLC: Codable, Identifiable {
    let id: String

    /// Sender's address (who locks funds)
    let sender: String

    /// Recipient's address (who can claim with preimage)
    let recipient: String

    /// Currency being locked
    let currency: String

    /// Amount locked in contract
    let amount: UInt64

    /// SHA-256 hash of the secret preimage
    let hashLock: Data

    /// Unix timestamp (milliseconds) after which sender can reclaim
    let timeLock: UInt64

    /// Transaction ID that created this HTLC
    let fundingTxId: String

    /// Current state of the contract
    var state: HTLCState

    /// Preimage that unlocks the hash (if revealed)
    var preimage: Data?

    /// Transaction ID that claimed/refunded this HTLC
    var settlementTxId: String?

    init(
        sender: String,
        recipient: String,
        currency: String,
        amount: UInt64,
        hashLock: Data,
        timeLock: UInt64,
        fundingTxId: String
    ) {
        self.id = UUID().uuidString
        self.sender = sender
        self.recipient = recipient
        self.currency = currency
        self.amount = amount
        self.hashLock = hashLock
        self.timeLock = timeLock
        self.fundingTxId = fundingTxId
        self.state = .pending
        self.preimage = nil
        self.settlementTxId = nil
    }

    /// Verify that a preimage matches the hash lock
    func verifyPreimage(_ preimage: Data) -> Bool {
        let hash = SHA256.hash(data: preimage)
        return Data(hash) == hashLock
    }

    /// Check if timelock has expired
    func isExpired() -> Bool {
        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        return now > timeLock
    }

    /// Check if contract can be claimed by recipient
    func canClaim(preimage: Data) -> Bool {
        return state == .pending && !isExpired() && verifyPreimage(preimage)
    }

    /// Check if sender can refund (after timelock expires)
    func canRefund() -> Bool {
        return state == .pending && isExpired()
    }

    /// Claim the HTLC with preimage
    mutating func claim(preimage: Data, txId: String) -> Bool {
        guard canClaim(preimage: preimage) else {
            return false
        }

        self.preimage = preimage
        self.settlementTxId = txId
        self.state = .claimed
        return true
    }

    /// Refund the HTLC (sender reclaims after timeout)
    mutating func refund(txId: String) -> Bool {
        guard canRefund() else {
            return false
        }

        self.settlementTxId = txId
        self.state = .refunded
        return true
    }
}

/// HTLC state
enum HTLCState: String, Codable {
    case pending    // Waiting for claim or timeout
    case claimed    // Successfully claimed by recipient
    case refunded   // Refunded to sender after timeout
    case cancelled  // Cancelled before funding
}

/// Atomic swap coordinator - manages cross-currency swaps using HTLCs
struct AtomicSwap: Codable, Identifiable {
    let id: String

    /// Party A details
    let partyA: SwapParty

    /// Party B details
    let partyB: SwapParty

    /// Secret for the swap (known only to initiator initially)
    var secret: Data?

    /// Hash of the secret (known to both parties)
    let secretHash: Data

    /// Time limit for the swap (seconds)
    let swapTimeout: UInt64

    /// Current state of the swap
    var state: SwapState

    /// HTLCs for this swap
    var htlcs: [String: HTLC] // currency -> HTLC

    /// Creation timestamp
    let createdAt: Date

    init(
        partyA: SwapParty,
        partyB: SwapParty,
        secret: Data,
        swapTimeout: UInt64 = 3600 // 1 hour default
    ) {
        self.id = UUID().uuidString
        self.partyA = partyA
        self.partyB = partyB
        self.secret = secret
        self.secretHash = Data(SHA256.hash(data: secret))
        self.swapTimeout = swapTimeout
        self.state = .initiated
        self.htlcs = [:]
        self.createdAt = Date()
    }

    /// Add HTLC to the swap
    mutating func addHTLC(_ htlc: HTLC) {
        htlcs[htlc.currency] = htlc
    }

    /// Check if all HTLCs are funded
    func isFullyFunded() -> Bool {
        return htlcs.count == 2 && htlcs.values.allSatisfy { $0.state == .pending }
    }

    /// Execute swap (claim all HTLCs with preimage)
    mutating func execute(secret: Data) -> Bool {
        guard isFullyFunded(),
              Data(SHA256.hash(data: secret)) == secretHash else {
            return false
        }

        self.secret = secret
        state = .completed
        return true
    }

    /// Cancel swap (refund all HTLCs)
    mutating func cancel() {
        state = .cancelled
    }
}

/// Swap party details
struct SwapParty: Codable {
    let address: String
    let currency: String
    let amount: UInt64
}

/// Swap state
enum SwapState: String, Codable {
    case initiated   // Swap created, waiting for HTLCs
    case funded      // All HTLCs funded
    case completed   // Swap executed successfully
    case cancelled   // Swap cancelled
    case expired     // Swap timed out
}

// MARK: - Swap Helper Functions

extension AtomicSwap {
    /// Create a fair swap proposal
    /// Uses exchange rate to calculate equivalent amounts
    static func createProposal(
        partyAAddress: String,
        partyACurrency: String,
        partyAAmount: UInt64,
        partyBAddress: String,
        partyBCurrency: String,
        exchangeRate: Double,
        partyADecimals: Int,
        partyBDecimals: Int
    ) -> AtomicSwap {
        // Generate random secret
        var secretBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &secretBytes)
        let secret = Data(secretBytes)

        // Calculate equivalent amount in currency B
        // Formula: amountB = amountA * rate * (10^decB / 10^decA)
        let amountAValue = Double(partyAAmount) / pow(10.0, Double(partyADecimals))
        let amountBValue = amountAValue * exchangeRate
        let partyBAmount = UInt64(amountBValue * pow(10.0, Double(partyBDecimals)))

        let partyA = SwapParty(
            address: partyAAddress,
            currency: partyACurrency,
            amount: partyAAmount
        )

        let partyB = SwapParty(
            address: partyBAddress,
            currency: partyBCurrency,
            amount: partyBAmount
        )

        return AtomicSwap(partyA: partyA, partyB: partyB, secret: secret)
    }

    /// Verify swap fairness using exchange rate
    func verifyFairness(exchangeRate: Double, toleranceBps: Int = 100) -> Bool {
        // Allow 1% tolerance (100 basis points)
        let expectedRatio = exchangeRate
        let actualRatio = Double(partyB.amount) / Double(partyA.amount)
        let deviation = abs(actualRatio - expectedRatio) / expectedRatio

        return deviation <= Double(toleranceBps) / 10000.0
    }
}
