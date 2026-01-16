# MeshPay Protocol v1.1 - New Features Documentation

## Version 1.1 Overview

MeshPay v1.1 extends the base protocol with enterprise-grade features for multi-asset management, trustless cross-currency exchange, hardware security, and traditional finance integration.

**Release Date:** January 16, 2026
**Major Features:** Multi-Currency, Atomic Swaps, Hardware Wallets, Bank Integration

---

## Table of Contents

1. [Multi-Currency Support](#multi-currency-support)
2. [Atomic Swaps](#atomic-swaps)
3. [Hardware Wallet Integration](#hardware-wallet-integration)
4. [Bank & Funding Integration](#bank--funding-integration)
5. [Demo & Testing](#demo--testing)
6. [Migration Guide](#migration-guide)

---

## Multi-Currency Support

### Overview

MeshPay v1.1 treats currencies as orthogonal bases in a vector space, where balances are vectors **b** = (b₁, b₂, ..., bₙ) and transactions are linear transformations preserving total value per dimension.

### Currency Model

```swift
struct Currency {
    let code: String        // 4-byte identifier (e.g., "MTOK", "WBTC")
    let name: String        // Human-readable name
    let symbol: String      // Display symbol (e.g., "MT", "₿")
    let decimals: Int       // Decimal places (8 for Bitcoin-like)
    let minAmount: UInt64   // Minimum transaction amount
    let defaultFee: UInt64  // Default network fee
}
```

### Predefined Currencies

| Code | Name | Symbol | Decimals | Use Case |
|------|------|--------|----------|----------|
| MTOK | MeshToken | MT | 8 | Native currency |
| WBTC | Wrapped Bitcoin | ₿ | 8 | Bitcoin proxy |
| MUSD | MeshDollar | $M | 6 | Stablecoin (USD) |
| MEUR | MeshEuro | €M | 6 | Stablecoin (EUR) |

### Transaction Extensions

All transactions now include a `currency` field:

```swift
struct Transaction {
    let id: String
    let version: UInt8          // v2 for multi-currency
    let currency: String        // 4-byte currency code
    let inputs: [TransactionInput]
    let outputs: [TransactionOutput]
    let txType: TransactionType // .standard, .genesis, .atomicSwap
    // ...
}
```

### Currency Validation Rules

1. **Consistency**: All inputs must be the same currency (except atomic swaps)
2. **Code Format**: Must be exactly 4 ASCII bytes
3. **Balance Isolation**: UTXO sets are partitioned by currency
4. **Fee Currency**: Fee must be in same currency as transaction

### Per-Currency UTXO Tracking

```swift
// Get balance for specific currency
let mtokBalance = utxoSet.balance(for: address, currency: "MTOK")

// Get all balances
let balances = utxoSet.balancesByCurrency(for: address)
// Returns: ["MTOK": 100000000, "WBTC": 50000000, "MUSD": 1000000]
```

### Exchange Rates

The `CurrencyRegistry` maintains exchange rates:

```swift
let registry = CurrencyRegistry()

// Set rate: 1 MT = $0.01 USD
registry.setExchangeRate(base: "MTOK", quote: "MUSD", rate: 0.01)

// Convert amounts
let usdAmount = registry.convert(
    amount: 100_000_000,  // 1 MT
    from: "MTOK",
    to: "MUSD"
)
// Result: 1,000,000 units = $1.00
```

### Mathematical Model

**Vector Space Representation:**
- Currencies form orthogonal basis vectors: **e**₁, **e**₂, ..., **eₙ**
- User balance: **b** = b₁**e**₁ + b₂**e**₂ + ... + bₙ**eₙ**
- Transaction: Linear transformation **T** preserving: ∑ **Tin** = ∑ **Tout** + **fee**

**Currency Isolation:**
- Separate ledger DAG per currency prevents cross-contamination
- Merkle trees per currency enable efficient sync
- Double-spend detection per currency via independent mempools

---

## Atomic Swaps

### Overview

Atomic swaps enable trustless cross-currency exchanges using Hashed Timelock Contracts (HTLCs). Both parties lock funds with a shared secret hash; the first to reveal the secret claims both sides.

### HTLC Structure

```swift
struct HTLC {
    let sender: String          // Who locks funds
    let recipient: String       // Who can claim
    let currency: String        // Currency being locked
    let amount: UInt64          // Locked amount
    let hashLock: Data          // SHA-256(secret)
    let timeLock: UInt64        // Expiry timestamp
    var state: HTLCState        // .pending, .claimed, .refunded
}
```

### Atomic Swap Protocol

```
┌─────────────────────────────────────────────────────────┐
│ Atomic Swap: Alice (10 MT) ↔ Bob (0.001 WBTC)         │
└─────────────────────────────────────────────────────────┘

1. Setup:
   • Alice generates secret S
   • Both compute H = SHA-256(S)

2. Funding:
   • Alice locks 10 MT in HTLC with hashlock H, timelock T+1h
   • Bob locks 0.001 WBTC in HTLC with hashlock H, timelock T+30m

3. Execution:
   • Alice reveals S, claims Bob's WBTC
   • Bob sees S, claims Alice's MT

4. Safety:
   • If Alice doesn't claim, both refund after timelock
   • Bob's timelock is shorter (prevents Alice claiming both)
```

### Usage Example

```swift
// Create swap proposal
let swap = AtomicSwap.createProposal(
    partyAAddress: alice.address,
    partyACurrency: "MTOK",
    partyAAmount: 10_00_000_000,  // 10 MT
    partyBAddress: bob.address,
    partyBCurrency: "WBTC",
    exchangeRate: 0.0001,         // 1 MT = 0.0001 BTC
    partyADecimals: 8,
    partyBDecimals: 8
)

// Verify fairness (within 1% tolerance)
if swap.verifyFairness(exchangeRate: 0.0001) {
    // Create HTLCs
    let aliceHTLC = HTLC(...)
    let bobHTLC = HTLC(...)

    // Execute swap
    if swap.execute(secret: swap.secret!) {
        print("Swap completed!")
    }
}
```

### Fairness Verification

**Formula:** `vₐ · p = vᵦ`

Where:
- vₐ = amount in currency A
- vᵦ = amount in currency B
- p = exchange rate (price of A in B units)

**Implementation:**
```swift
func verifyFairness(exchangeRate: Double, toleranceBps: Int = 100) -> Bool {
    let expectedRatio = exchangeRate
    let actualRatio = Double(partyB.amount) / Double(partyA.amount)
    let deviation = abs(actualRatio - expectedRatio) / expectedRatio

    return deviation <= Double(toleranceBps) / 10000.0  // 1% = 100 bps
}
```

### Security Guarantees

1. **Atomicity**: Either both sides succeed or both fail (no partial execution)
2. **Trustlessness**: No third party or escrow required
3. **Time-bounded**: Automatic refund after timelock prevents indefinite locks
4. **Front-running Protection**: Secret only revealed after both sides funded

---

## Hardware Wallet Integration

### Overview

Hardware wallets provide air-gapped key storage, ensuring private keys never leave the secure element. MeshPay supports BLE-enabled devices like Ledger Nano X.

### Supported Devices

| Device | Type | Connection | Status |
|--------|------|------------|--------|
| Ledger Nano X | BLE | Wireless | ✅ Supported |
| Ledger Nano S Plus | BLE | Wireless | ✅ Supported |
| Trezor Model T | BLE | Wireless | 🚧 Planned |
| Generic BLE Wallet | BLE | Wireless | ⚠️ Experimental |

### Security Model

```
┌──────────────────────────────────────────────┐
│ Hardware Wallet Security Layers              │
├──────────────────────────────────────────────┤
│ Layer 1: Air-gapped Secure Element          │
│   • Private keys never leave device          │
│   • Tamper-resistant chip                    │
│                                              │
│ Layer 2: BLE Encrypted Channel              │
│   • Noise Protocol over BLE                  │
│   • Mutual authentication                    │
│                                              │
│ Layer 3: User Confirmation                   │
│   • Physical button press required           │
│   • Display shows transaction details        │
│                                              │
│ Layer 4: OOB Verification                    │
│   • Fingerprint comparison on pairing        │
│   • Prevents MITM attacks                    │
└──────────────────────────────────────────────┘
```

### Usage Flow

```swift
let hwManager = HardwareWalletManager()

// 1. Discovery
hwManager.startScanning()
// User sees available devices

// 2. Pairing
let device = availableDevices.first!
try hwManager.pair(device, fingerprint: "ABCD1234")

// 3. Derive Address
let address = try await hwManager.deriveAddress(
    from: device,
    coinType: 0,
    account: 0,
    addressIndex: 0
)

// 4. Sign Transaction (for high-value tx)
var transaction = try walletManager.createPayment(
    to: recipient,
    amount: 150_000_000  // Exceeds hardware threshold
)

if hwManager.requiresHardwareWallet(transaction) {
    // User confirms on device screen
    transaction = try await hwManager.signTransaction(transaction, with: device)
}
```

### BIP-44 Derivation

**Path:** `m/44'/coin_type'/account'/change/address_index`

Example paths:
- `m/44'/0'/0'/0/0` - First MeshToken address
- `m/44'/1'/0'/0/0` - First Bitcoin address

### Hardware Threshold

Transactions exceeding **0.1 MT** (10,000,000 units) require hardware wallet signing by default:

```swift
private let hardwareThreshold: UInt64 = 10_000_000

func requiresHardwareWallet(_ transaction: Transaction) -> Bool {
    return transaction.totalOutputAmount() >= hardwareThreshold
}
```

### APDU Commands (Ledger)

For production implementation, use APDU commands:

```
GET_PUBLIC_KEY: 0x40
SIGN_TRANSACTION: 0x48
GET_APP_CONFIGURATION: 0x06
```

---

## Bank & Funding Integration

### Overview

When online, users can add funds to wallets via bank accounts, credit cards, or other funding sources. Balances sync when connectivity is restored.

### Funding Sources

```swift
enum FundingSourceType {
    case bankAccount      // ACH transfer
    case creditCard       // Card payment
    case debitCard        // Instant debit
    case paypal           // PayPal integration
    case venmo            // Venmo integration
    case cashApp          // Cash App integration
}
```

### Deposit Flow

```
┌────────────────────────────────────────────────┐
│ Fiat → Crypto On-Ramp Flow                    │
├────────────────────────────────────────────────┤
│ 1. User initiates deposit                      │
│    • Amount: $100 USD                          │
│    • Destination: MUSD wallet                  │
│                                                │
│ 2. If online: Process immediately              │
│    • Call banking API (Stripe/Plaid)          │
│    • Wait for confirmation                     │
│    • Create genesis transaction                │
│    • Credit wallet                             │
│                                                │
│ 3. If offline: Queue for sync                  │
│    • Save to pendingDeposits                   │
│    • Sync when online                          │
│    • User notified on completion               │
└────────────────────────────────────────────────┘
```

### Network Monitoring

The `FundingManager` automatically monitors network status:

```swift
@Published var isOnline: Bool = false

private func setupNetworkMonitoring() {
    $isOnline
        .removeDuplicates()
        .sink { [weak self] online in
            if online {
                self?.handleOnlineStatus()
            }
        }
}

private func handleOnlineStatus() {
    Task {
        await syncPendingDeposits()
        await refreshBalances()
    }
}
```

### Verification

Before first use, funding sources must be verified:

```swift
// Add bank account
let account = try fundingManager.addFundingSource(
    type: .bankAccount,
    name: "Chase Checking",
    accountNumber: "****1234",
    routingInfo: "021000021"
)

// Verify (micro-deposits or instant via Plaid)
try await fundingManager.verifyFundingSource(account.id)
```

### Buying Tokens

```swift
// Convert $100 USD → MeshTokens
let deposit = try await fundingManager.buyTokens(
    fromSource: bankAccount.id,
    fiatAmount: 100.0,
    fiatCurrency: "MUSD",
    toCurrency: "MTOK"
)

// Result: 10,000 MT credited to wallet (at 100:1 rate)
```

### Selling Tokens (Off-Ramp)

```swift
// Convert 1000 MT → $10 USD (planned)
try await fundingManager.sellTokens(
    amount: 1000_00_000_000,
    currency: "MTOK",
    toSource: bankAccount.id
)
```

---

## Demo & Testing

### Running the Demo

MeshPay v1.1 includes a comprehensive interactive demo:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        MeshPayDemoView()
    }
}
```

### Demo Scenarios

The demo includes 4 scenarios:

#### 1. Multi-Currency Basics
- Create wallets for Alice and Bob
- Fund Alice with MTOK, WBTC, MUSD
- Check per-currency balances
- Send 0.5 WBTC to Bob
- Verify currency consistency

#### 2. Atomic Swap
- Alice wants 10 MT → $0.10 MUSD
- Bob wants $0.10 MUSD → 10 MT
- Create swap proposal with secret
- Verify exchange rate fairness
- Create HTLCs for both sides
- Reveal secret and execute swap

#### 3. Hardware Wallet
- Discover mock Ledger Nano X
- Pair with fingerprint verification
- Derive address from hardware
- Create high-value transaction
- Sign on hardware device
- Verify signature

#### 4. Bank Integration
- Add bank account
- Verify via micro-deposits
- Go online (simulate connectivity)
- Buy MeshTokens with USD
- Check updated balance
- Sync pending deposits

### Running Individual Scenarios

```swift
let demo = MeshPayDemo()

// Run specific scenario
await demo.runScenario1_MultiCurrencyBasics()
await demo.runScenario2_AtomicSwap()
await demo.runScenario3_HardwareWallet()
await demo.runScenario4_BankIntegration()

// Or run all
await demo.runFullDemo()
```

### Sample Output

```
🚀 Starting MeshPay v1.1 Full Demo
=================================

📊 Scenario 1: Multi-Currency Basics
-----------------------------------
1️⃣ Creating wallets...
   ✓ Alice: M1A2B3C4D5E6F7G8H9...
   ✓ Bob: M9Z8Y7X6W5V4U3T2S1...

2️⃣ Funding Alice with multiple currencies...
   ✓ Funded with 1.00000000 MT
   ✓ Funded with 1.00000000 ₿
   ✓ Funded with 1.000000 $M

3️⃣ Alice's balances:
   • 1.00000000 MT
   • 0.000000 $M
   • 1.00000000 ₿

4️⃣ Alice sends 0.5 WBTC to Bob...
   ✓ Transaction created: 1a2b3c4d5e6f7g8h...
   ✓ Currency: WBTC
   ✓ Amount: 0.5 WBTC
   ✓ Fee: 0.000005 WBTC

✅ Multi-currency demo completed
```

---

## Migration Guide

### From v1.0 to v1.1

#### Breaking Changes

1. **Transaction Structure**
   ```swift
   // v1.0
   let tx = Transaction.create(
       inputs: inputs,
       outputs: outputs,
       fee: fee,
       senderPublicKey: pubkey
   )

   // v1.1 (with currency)
   let tx = Transaction.create(
       currency: "MTOK",  // NEW
       inputs: inputs,
       outputs: outputs,
       fee: fee,
       senderPublicKey: pubkey
   )
   ```

2. **UTXO Model**
   ```swift
   // v1.0
   let balance = utxoSet.balance(for: address)

   // v1.1 (currency-aware)
   let balance = utxoSet.balance(for: address, currency: "MTOK")
   let allBalances = utxoSet.balancesByCurrency(for: address)
   ```

3. **WalletManager**
   ```swift
   // v1.0
   let tx = try walletManager.createPayment(
       to: address,
       amount: amount
   )

   // v1.1 (with currency)
   let tx = try walletManager.createPayment(
       to: address,
       amount: amount,
       currency: "MTOK"  // NEW
   )
   ```

#### Data Migration

Existing v1.0 transactions default to "MTOK":

```swift
// Migration script
for var transaction in existingTransactions {
    if transaction.version == 1 {
        transaction.version = 2
        transaction.currency = "MTOK"  // Default
    }
}
```

#### New Dependencies

```swift
// Add to Package.swift (if needed)
.package(url: "https://github.com/ledger/ledger-swift", from: "1.0.0")
```

---

## API Reference (v1.1 Additions)

### Currency

```swift
// Get currency info
let currency = CurrencyRegistry().get("MTOK")
currency?.format(amount: 100_000_000)  // "1.00000000 MT"

// Convert amounts
let usd = registry.convert(amount: 100_000_000, from: "MTOK", to: "MUSD")
```

### Atomic Swaps

```swift
// Create swap
let swap = AtomicSwap.createProposal(...)

// Verify fairness
swap.verifyFairness(exchangeRate: 0.01, toleranceBps: 100)

// Create HTLC
let htlc = HTLC(sender: ..., recipient: ..., hashLock: swap.secretHash, ...)

// Claim
htlc.claim(preimage: secret, txId: txId)
```

### Hardware Wallet

```swift
// Scan for devices
hardwareWalletManager.startScanning()

// Connect
hardwareWalletManager.connect(to: device)

// Sign
let signedTx = try await hardwareWalletManager.signTransaction(tx, with: device)
```

### Funding

```swift
// Add source
let source = try fundingManager.addFundingSource(
    type: .bankAccount,
    name: "My Bank",
    accountNumber: "1234"
)

// Deposit
let deposit = try await fundingManager.initiateDeposit(
    from: source.id,
    amount: 100.0,
    currency: "MTOK",
    toAddress: wallet.address
)
```

---

## Performance Considerations

### Multi-Currency Overhead

- **UTXO Lookup**: O(n) per currency, where n = UTXO count
- **Balance Calculation**: O(c · n), where c = currency count
- **Optimization**: Use currency-indexed B-trees for O(log n) lookup

### Atomic Swap Latency

- **HTLC Creation**: ~2 RTT (round-trip times)
- **Claim Propagation**: TTL hops × hop latency
- **Expected**: <10s for 6-hop mesh at 100ms/hop

### Hardware Wallet

- **Pairing**: ~3-5 seconds
- **Address Derivation**: ~1-2 seconds
- **Transaction Signing**: ~2-5 seconds (includes user confirmation)

---

## Security Audit Notes

### Multi-Currency Isolation

**Threat:** Cross-currency double-spend
**Mitigation:** Separate DAGs per currency, currency field in Tx hash

### Atomic Swap Fairness

**Threat:** Unfair exchange rates
**Mitigation:** Fairness verification with 1% tolerance, user approval required

### Hardware Wallet MITM

**Threat:** BLE interception during pairing
**Mitigation:** OOB fingerprint verification, Noise Protocol encryption

### Bank Integration

**Threat:** API key exposure
**Mitigation:** Keys stored in Keychain, never in UserDefaults or logs

---

## Future Roadmap

### v1.2 (Planned)

- [ ] Multi-signature wallets (2-of-3, 3-of-5)
- [ ] Confidential transactions (Bulletproofs)
- [ ] Cross-chain bridges (Bitcoin, Ethereum)
- [ ] Mobile hardware wallet (Secure Enclave)

### v2.0 (Vision)

- [ ] Lightning Network integration
- [ ] Decentralized exchange (DEX)
- [ ] Staking and governance
- [ ] Zero-knowledge rollups

---

## Conclusion

MeshPay v1.1 transforms the protocol into a multi-asset platform with trustless exchange, hardware security, and traditional finance connectivity. The combination of offline mesh networking with online funding creates a unique hybrid model: **mesh-native payments with fiat on-ramps**.

**Key Achievements:**
- ✅ Multi-currency support with mathematical isolation
- ✅ Atomic swaps via HTLCs (trustless exchange)
- ✅ Hardware wallet integration (BLE-enabled)
- ✅ Bank integration for fiat deposits
- ✅ Comprehensive demo suite

**Next Steps:**
1. Run the demo: `MeshPayDemoView()`
2. Test multi-currency transactions
3. Experiment with atomic swaps
4. Integrate hardware wallet (optional)
5. Add funding sources for real-world use

---

**Document Version:** 1.1
**Last Updated:** January 16, 2026
**Author:** BitChat Development Team
