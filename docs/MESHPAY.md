# MeshPay Protocol Implementation

## Overview

MeshPay is a decentralized peer-to-peer payment protocol built on top of BitChat's BLE mesh networking infrastructure. It enables secure, private, offline value transfers without reliance on internet connectivity, central servers, or user identifiers.

**Version:** 1.0
**Date:** January 16, 2026
**Status:** Initial Implementation

---

## Table of Contents

1. [Architecture](#architecture)
2. [Key Features](#key-features)
3. [Components](#components)
4. [Transaction Flow](#transaction-flow)
5. [Security](#security)
6. [Usage](#usage)
7. [API Reference](#api-reference)
8. [Testing](#testing)
9. [Future Work](#future-work)

---

## Architecture

MeshPay extends BitChat's layered architecture with a payment protocol layer:

```
┌─────────────────────────────────────┐
│     Application Layer (UI)          │
│  WalletView | SendPaymentView       │
└─────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────┐
│   Payment Protocol Layer (NEW)      │
│  PaymentService | WalletManager     │
└─────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────┐
│   Session Layer (Extended)          │
│  Packet Routing | TTL Management    │
└─────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────┐
│   Encryption Layer (BitChat)        │
│  Noise Protocol | E2E Encryption    │
└─────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────┐
│   Transport Layer (BLE Mesh)        │
│  Gossip Protocol | Multi-hop        │
└─────────────────────────────────────┘
```

### Design Principles

1. **UTXO Model**: Bitcoin-style unspent transaction outputs for double-spend prevention
2. **Gossip Propagation**: Epidemic-style transaction broadcasting through mesh
3. **Cryptographic Security**: secp256k1 for signatures, Ed25519 for identity
4. **Eventual Consistency**: DAG-based transaction ordering with probabilistic finality
5. **Offline-First**: No internet required, full mesh network operation

---

## Key Features

### ✅ Implemented

- **Wallet Management**: Create, import, and manage multiple wallets
- **UTXO Tracking**: Bitcoin-compatible unspent transaction output model
- **Transaction Creation**: Build and sign transactions with inputs/outputs
- **Signature Validation**: ECDSA (secp256k1) signature verification
- **Balance Calculation**: Real-time balance updates from UTXO set
- **Payment Address Generation**: Bitcoin-style Base58Check addresses (0x4D prefix)
- **Transaction History**: Persistent storage of confirmed transactions
- **Payment Requests**: QR-code compatible payment request format
- **Protocol Extensions**: New message types for payment broadcasting

### 🚧 In Progress

- **BLE Packet Handling**: Integration with BLEService for packet transmission
- **Gossip Implementation**: Transaction propagation through mesh network
- **Double-Spend Detection**: Mempool conflict detection and resolution
- **Confirmation Tracking**: Probabilistic finality via hop counting
- **UI Polish**: Complete payment interface with QR scanning

### 📋 Planned

- **Conflict Voting**: Byzantine fault-tolerant double-spend resolution
- **Zero-Knowledge Proofs**: Amount privacy with Bulletproofs
- **Multi-Signature**: Threshold signatures for shared wallets
- **Lightning Integration**: Optional settlement to Bitcoin Lightning
- **Hardware Wallet Support**: Secure key storage
- **Multi-Asset Support**: Multiple token types

---

## Components

### 1. Data Models

#### `PaymentIdentity`
Represents payment keys and address.

```swift
struct PaymentIdentity {
    let privateKey: Data      // secp256k1 (32 bytes)
    let publicKey: Data       // Compressed public key (33 bytes)
    let address: String       // Base58-encoded address
    let createdAt: Date
}
```

**Key Features:**
- Bitcoin-compatible key derivation
- Base58Check address encoding with 0x4D version byte
- RIPEMD-160(SHA-256(pubkey)) address format

#### `Transaction`
Core transaction structure using UTXO model.

```swift
struct Transaction {
    let id: String                          // SHA-256 hash
    let version: UInt8                      // Protocol version
    var inputs: [TransactionInput]          // UTXOs being spent
    let outputs: [TransactionOutput]        // New UTXOs created
    let fee: UInt64                         // Transaction fee
    let timestamp: UInt64                   // Unix millis
    var memo: String?                       // Optional message
    let senderPublicKey: Data              // Sender's public key
    var signature: Data?                    // Ed25519 signature
    var confirmations: UInt32               // Hop count
}
```

**Validation Rules:**
- All inputs must reference existing UTXOs
- Sum(inputs) ≥ Sum(outputs) + fee
- Valid ECDSA signature over transaction hash
- Timestamp within 1 hour of current time
- No duplicate inputs

#### `UTXO` (Unspent Transaction Output)
Tracks spendable outputs.

```swift
struct UTXO {
    let transactionId: String
    let outputIndex: UInt32
    let output: TransactionOutput
    let height: UInt32
    var isSpent: Bool
    var spentBy: String?
}
```

#### `Wallet`
User wallet containing payment identity and metadata.

```swift
struct Wallet {
    let identity: PaymentIdentity
    var label: String
    let createdAt: Date
    var isDefault: Bool
}
```

### 2. Services

#### `WalletManager`
Manages wallets, UTXOs, and balances.

**Responsibilities:**
- Wallet creation and import
- UTXO set management
- Balance calculation (confirmed + pending)
- Transaction creation
- Persistence (UserDefaults for now)

**Key Methods:**
```swift
func createWallet(label: String) throws -> Wallet
func createPayment(to: String, amount: UInt64, fee: UInt64) throws -> Transaction
func addTransaction(_ transaction: Transaction, height: UInt32)
func getBalance(for address: String) -> WalletBalance
```

#### `PaymentService`
Core payment protocol logic.

**Responsibilities:**
- Transaction validation
- Mempool management
- Double-spend detection
- Transaction propagation
- Conflict resolution
- Payment request handling

**Key Methods:**
```swift
func sendPayment(to: String, amount: UInt64) async throws -> Transaction
func handleReceivedTransaction(_ tx: Transaction, from: PeerID)
func confirmTransaction(_ txId: String, height: UInt32)
func queryBalanceFromPeers(_ address: String)
```

### 3. Protocol Extensions

#### New Message Types (BitchatProtocol.swift)

```swift
enum MessageType: UInt8 {
    case paymentTx = 0x30          // Transaction broadcast
    case balanceQuery = 0x31       // Balance query
    case balanceResponse = 0x32    // Balance response
    case conflictVote = 0x33       // Double-spend vote
}
```

#### New Noise Payload Types

```swift
enum NoisePayloadType: UInt8 {
    case paymentRequest = 0x20     // Private payment request
    case payment = 0x21            // Private payment
    case paymentReceipt = 0x22     // Payment confirmation
}
```

#### Transport Protocol Extensions

```swift
protocol Transport {
    func broadcastTransaction(_ transaction: Transaction)
    func sendPaymentRequest(_ request: PaymentRequest, to peerID: PeerID)
    func queryBalance(_ address: String)
    func respondToBalanceQuery(peerID: PeerID, queryId: String, balance: UInt64)
    func sendConflictVote(_ vote: ConflictVotePacket)
}
```

### 4. User Interface

#### `WalletView`
Main wallet interface showing:
- Current balance (confirmed + pending)
- UTXO count
- Payment address
- Transaction history
- Send/Receive buttons

#### `SendPaymentView`
Payment sending interface:
- Recipient address input (with QR scanner)
- Amount input with validation
- Optional memo field
- Fee display
- Send confirmation

#### `ReceivePaymentView`
Payment receiving interface:
- QR code display
- Payment address
- Optional amount/label/message
- Copy address button

---

## Transaction Flow

### 1. Creating a Payment

```
User Input → Validate Address → Select UTXOs → Build Transaction → Sign → Broadcast
```

**Detailed Steps:**

1. **User initiates payment**
   - Enter recipient address
   - Enter amount (in tokens)
   - Optional memo

2. **WalletManager validates and creates transaction**
   ```swift
   let tx = try walletManager.createPayment(
       to: recipientAddress,
       amount: amountInUnits,
       fee: 1000
   )
   ```

3. **Transaction structure:**
   - **Inputs**: Selected UTXOs totaling ≥ amount + fee
   - **Outputs**:
     - Recipient output (amount)
     - Change output (if needed)
   - **Signature**: ECDSA over transaction hash

4. **PaymentService broadcasts**
   ```swift
   let tx = try await paymentService.sendPayment(...)
   ```

### 2. Receiving and Validating

```
Receive Packet → Deduplicate → Validate → Mempool → Propagate → Confirm
```

**Validation Steps:**

1. **Deduplication**: Check if transaction ID already seen
2. **Signature validation**: Verify ECDSA signature
3. **Input validation**: Ensure all inputs exist in UTXO set
4. **Amount validation**: Sum(inputs) ≥ Sum(outputs) + fee
5. **Double-spend check**: Check for conflicting transactions
6. **Add to mempool**: Queue for confirmation
7. **Propagate**: Rebroadcast to mesh (gossip)

### 3. Confirmation Process

Transactions gain confirmations as they propagate through the mesh:

- **Confirmation threshold**: 6 hops (configurable)
- **Probability model**: P(finality) ≈ 1 - (1 - p)^k
  - p = per-link delivery probability (~0.8 for BLE)
  - k = hop count

**Confirmation States:**
- 0-2 confirmations: Pending
- 3-5 confirmations: Low confidence
- 6+ confirmations: Confirmed (moved to history)

### 4. Double-Spend Handling

If two transactions spend the same UTXO:

1. **Detection**: Compare input references in mempool
2. **Conflict creation**: Create `TransactionConflict` record
3. **Voting** (future): Peers vote based on:
   - Timestamp (earlier wins)
   - Trust scores
   - Seen order
4. **Resolution**: Keep winning transaction, reject others

---

## Security

### Cryptographic Primitives

| Purpose | Algorithm | Key Size |
|---------|-----------|----------|
| Transaction Signing | ECDSA (secp256k1) | 256 bits |
| Identity Signing | Ed25519 | 256 bits |
| Session Encryption | Noise_XX_25519 | 256 bits |
| Hashing | SHA-256 | 256 bits |
| Address Derivation | RIPEMD-160 | 160 bits |

### Threat Mitigation

#### 1. Double-Spend Attack
**Mitigation:**
- UTXO tracking prevents spending same output twice
- Mempool conflict detection
- Gossip-based consensus (timestamp + trust voting)
- Probabilistic finality after 6 confirmations

**Success Probability:**
- Attacker needs >50% mesh control
- P(success) < 2^-40 after 6 confirmations

#### 2. Transaction Forgery
**Mitigation:**
- ECDSA signatures with secp256k1
- Public key recovery from signature
- Hash-based transaction IDs

#### 3. Replay Attack
**Mitigation:**
- Timestamp validation (±1 hour window)
- Nonce-based deduplication
- UTXO consumed after spending

#### 4. Sybil Attack
**Mitigation:**
- Trust score system (based on transaction history)
- Rate limiting on connections
- Social graph filtering (BitChat's existing mechanism)

#### 5. Man-in-the-Middle
**Mitigation:**
- End-to-end encryption (Noise Protocol)
- Mutual authentication
- Forward secrecy

### Privacy Features

1. **Anonymity**: No persistent identifiers; addresses are pseudonymous
2. **Deniability**: Signatures repudiable outside mesh context
3. **Traffic Analysis Resistance**: Packet padding (from BitChat)
4. **Amount Privacy** (future): Bulletproofs for confidential transactions

---

## Usage

### Creating a Wallet

```swift
// Initialize managers
let walletManager = WalletManager()
let paymentService = PaymentService(walletManager: walletManager)

// Create new wallet
let wallet = try walletManager.createWallet(label: "My Wallet")
print("Address: \(wallet.identity.address)")
```

### Sending a Payment

```swift
// Send 1.5 MeshTokens
let transaction = try await paymentService.sendPayment(
    to: "M1A2B3C4D5E6F7G8H9...",
    amount: 150_000_000,  // 1.5 MT in units
    fee: 1000,
    memo: "Payment for coffee"
)

print("Transaction ID: \(transaction.id)")
```

### Checking Balance

```swift
let balance = walletManager.balance

print("Confirmed: \(balance.confirmedTokens) MT")
print("Pending: \(balance.pendingTokens) MT")
print("UTXOs: \(balance.utxoCount)")
```

### Receiving Payments

```swift
// Create payment request
let request = try paymentService.createPaymentRequest(
    amount: 50_000_000,  // 0.5 MT
    label: "Coffee payment",
    message: "Thanks for the coffee!"
)

// Generate QR code string
let qrString = request.toQRString()
// Format: meshpay:M1A2B3...?amount=50000000&label=Coffee%20payment
```

### Handling Received Transactions

```swift
// In BLEService packet handler
func handlePaymentTx(_ packet: BitchatPacket) {
    let tx = try Transaction.decode(from: packet.payload)
    paymentService.handleReceivedTransaction(tx, from: packet.senderID)
}
```

---

## API Reference

### WalletManager

#### Methods

**`createWallet(label: String) throws -> Wallet`**
- Creates a new wallet with generated keys
- Sets as default if first wallet
- Persists to storage

**`createPayment(to: String, amount: UInt64, fee: UInt64, memo: String?) throws -> Transaction`**
- Selects UTXOs for payment
- Creates transaction with change output
- Signs with wallet's private key
- Returns unsigned transaction

**`addTransaction(_ transaction: Transaction, height: UInt32)`**
- Applies transaction to UTXO set
- Updates balance
- Persists changes

**`getBalance(for address: String) -> WalletBalance`**
- Calculates confirmed + pending balance
- Counts UTXOs
- Returns balance struct

### PaymentService

#### Methods

**`sendPayment(to: String, amount: UInt64, fee: UInt64, memo: String?) async throws -> Transaction`**
- Creates and signs transaction
- Adds to mempool
- Broadcasts to mesh
- Returns transaction

**`handleReceivedTransaction(_ transaction: Transaction, from peerID: PeerID)`**
- Deduplicates
- Validates transaction
- Detects double-spends
- Adds to mempool or rejects
- Propagates to peers

**`confirmTransaction(_ transactionId: String, height: UInt32)`**
- Moves from mempool to history
- Updates UTXO set
- Saves to persistent storage

**`queryBalanceFromPeers(_ address: String)`**
- Broadcasts balance query to mesh
- Collects responses
- Returns aggregated balance

### Transaction

#### Methods

**`static create(inputs: [TransactionInput], outputs: [TransactionOutput], fee: UInt64, ...) -> Transaction`**
- Calculates transaction ID (SHA-256 hash)
- Sets timestamp
- Returns unsigned transaction

**`mutating sign(with identity: PaymentIdentity) throws`**
- Signs transaction with secp256k1
- Signs each input individually
- Sets signature field

**`func verifySignature() -> Bool`**
- Verifies ECDSA signature
- Checks public key matches
- Returns validation result

**`func validate(utxoSet: [String: UTXO]) -> TransactionValidationResult`**
- Validates signature
- Checks inputs exist
- Verifies amounts
- Checks timestamp
- Returns .valid or .invalid(reason)

---

## Testing

### Unit Tests

Create tests in `bitchatTests/Payment/`:

```swift
class PaymentIdentityTests: XCTestCase {
    func testKeyGeneration() throws {
        let identity = try PaymentIdentity.generate()
        XCTAssertEqual(identity.privateKey.count, 32)
        XCTAssertEqual(identity.publicKey.count, 33)
    }

    func testAddressValidation() {
        let validAddress = "M1A2B3C4D5E6F7G8H9..."
        XCTAssertTrue(PaymentIdentity.isValidAddress(validAddress))

        let invalidAddress = "INVALID"
        XCTAssertFalse(PaymentIdentity.isValidAddress(invalidAddress))
    }
}

class TransactionTests: XCTestCase {
    func testTransactionCreation() throws {
        let identity = try PaymentIdentity.generate()
        let inputs = [TransactionInput(previousTxId: "test", outputIndex: 0)]
        let outputs = [TransactionOutput(address: "M1...", amount: 1000)]

        var tx = Transaction.create(
            inputs: inputs,
            outputs: outputs,
            fee: 100,
            senderPublicKey: identity.publicKey
        )

        try tx.sign(with: identity)
        XCTAssertTrue(tx.verifySignature())
    }
}
```

### Integration Tests

Test full payment flow:

```swift
class PaymentFlowTests: XCTestCase {
    func testFullPaymentFlow() async throws {
        // Setup
        let walletManager = WalletManager(storage: MemoryWalletStorage())
        let paymentService = PaymentService(walletManager: walletManager)

        // Create wallets
        let sender = try walletManager.createWallet(label: "Sender")
        let receiverIdentity = try PaymentIdentity.generate()

        // Fund sender with genesis transaction
        let genesis = try Transaction.genesis(
            recipients: [(address: sender.identity.address, amount: 10_000_000)],
            senderIdentity: sender.identity
        )
        walletManager.addTransaction(genesis, height: 0)

        // Send payment
        let tx = try await paymentService.sendPayment(
            to: receiverIdentity.address,
            amount: 5_000_000,
            fee: 1000
        )

        // Verify
        XCTAssertEqual(tx.outputs[0].address, receiverIdentity.address)
        XCTAssertEqual(tx.outputs[0].amount, 5_000_000)
        XCTAssertTrue(tx.verifySignature())
    }
}
```

---

## Future Work

### Short-term (v1.1)

1. **Complete BLE Integration**
   - Implement payment packet handlers in BLEService
   - Add transaction gossip protocol
   - Test multi-hop propagation

2. **Conflict Resolution**
   - Implement voting mechanism
   - Add trust score calculation
   - Test double-spend scenarios

3. **UI Enhancements**
   - Real QR scanner (AVFoundation)
   - Transaction details view
   - Payment notifications

### Medium-term (v1.5)

1. **Performance Optimization**
   - UTXO set indexing
   - Merkle tree for sync
   - Bloom filters for transaction queries

2. **Privacy Enhancements**
   - Bulletproofs for confidential amounts
   - Ring signatures for sender privacy
   - Stealth addresses

3. **Network Resilience**
   - Partition detection and healing
   - Checkpoint mechanism
   - Dispute resolution protocol

### Long-term (v2.0)

1. **Lightning Integration**
   - Payment channels
   - Routing through mesh
   - Watchtowers for dispute resolution

2. **Multi-Asset Support**
   - Colored coins
   - Atomic swaps
   - Asset issuance

3. **Hardware Wallet Support**
   - BLE hardware wallet integration
   - Secure element storage
   - Multi-signature workflows

---

## References

### Related Documents

- [BitChat Protocol Specification](./PROTOCOL.md)
- [Noise Protocol Framework](https://noiseprotocol.org/)
- [Bitcoin Developer Guide](https://bitcoin.org/en/developer-guide)
- [Bulletproofs Paper](https://eprint.iacr.org/2017/1066.pdf)

### Code Structure

```
bitchat/Payment/
├── Models/
│   ├── PaymentIdentity.swift       # Keys and address generation
│   ├── Transaction.swift           # Transaction structure
│   ├── TransactionInput.swift      # Input references
│   ├── TransactionOutput.swift     # Output definitions
│   ├── UTXO.swift                  # UTXO tracking
│   ├── Wallet.swift                # Wallet model
│   └── PaymentPackets.swift        # Protocol packets
├── Services/
│   ├── WalletManager.swift         # Wallet and UTXO management
│   └── PaymentService.swift        # Payment protocol logic
└── Views/
    ├── WalletView.swift            # Main wallet UI
    ├── SendPaymentView.swift       # Payment sending
    └── ReceivePaymentView.swift    # Payment receiving
```

---

## License

This implementation is part of the BitChat project, released into the public domain under the Unlicense.

For more information, see <https://unlicense.org>

---

**Document Version:** 1.0
**Last Updated:** January 16, 2026
**Maintainer:** BitChat Development Team
