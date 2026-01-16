import Foundation

// MARK: - Type Aliases for Protocol Integration
typealias MeshPayTransaction = Transaction
typealias MeshPayPaymentRequest = PaymentRequest

// MARK: - Payment Protocol Packets

/// Balance query packet
struct BalanceQueryPacket: Codable {
    /// Unique query identifier
    let queryId: String

    /// Address to query balance for
    let address: String

    /// Timestamp of query
    let timestamp: UInt64

    init(address: String) {
        self.queryId = UUID().uuidString
        self.address = address
        self.timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
    }

    /// Encode to binary data
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    /// Decode from binary data
    static func decode(from data: Data) throws -> BalanceQueryPacket {
        let decoder = JSONDecoder()
        return try decoder.decode(BalanceQueryPacket.self, from: data)
    }
}

/// Balance response packet
struct BalanceResponsePacket: Codable {
    /// Query ID this response is for
    let queryId: String

    /// Address balance
    let balance: UInt64

    /// Number of UTXOs
    let utxoCount: Int

    /// Responder's peer ID
    let responderPeerID: Data

    /// Timestamp of response
    let timestamp: UInt64

    init(queryId: String, balance: UInt64, utxoCount: Int, responderPeerID: Data) {
        self.queryId = queryId
        self.balance = balance
        self.utxoCount = utxoCount
        self.responderPeerID = responderPeerID
        self.timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
    }

    /// Encode to binary data
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    /// Decode from binary data
    static func decode(from data: Data) throws -> BalanceResponsePacket {
        let decoder = JSONDecoder()
        return try decoder.decode(BalanceResponsePacket.self, from: data)
    }
}

/// Conflict vote packet for double-spend resolution
struct ConflictVotePacket: Codable {
    /// Transaction IDs in conflict
    let conflictingTxIds: [String]

    /// Voted transaction ID (the one to keep)
    let votedTxId: String

    /// Voter's peer ID
    let voterPeerID: Data

    /// Trust score of voter (0.0 to 1.0)
    let trustScore: Double

    /// Vote timestamp
    let timestamp: UInt64

    /// Signature over vote data
    var signature: Data?

    init(conflictingTxIds: [String], votedTxId: String, voterPeerID: Data, trustScore: Double) {
        self.conflictingTxIds = conflictingTxIds
        self.votedTxId = votedTxId
        self.voterPeerID = voterPeerID
        self.trustScore = trustScore
        self.timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        self.signature = nil
    }

    /// Encode to binary data
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    /// Decode from binary data
    static func decode(from data: Data) throws -> ConflictVotePacket {
        let decoder = JSONDecoder()
        return try decoder.decode(ConflictVotePacket.self, from: data)
    }
}

/// Transaction broadcast packet (wraps Transaction for network transmission)
struct TransactionBroadcastPacket: Codable {
    /// The transaction being broadcast
    let transaction: Transaction

    /// Number of hops this broadcast has made
    var hopCount: UInt8

    /// Originating peer ID
    let originPeerID: Data

    /// Broadcast timestamp
    let broadcastTimestamp: UInt64

    init(transaction: Transaction, originPeerID: Data) {
        self.transaction = transaction
        self.hopCount = 0
        self.originPeerID = originPeerID
        self.broadcastTimestamp = UInt64(Date().timeIntervalSince1970 * 1000)
    }

    /// Encode to binary data (compact format)
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    /// Decode from binary data
    static func decode(from data: Data) throws -> TransactionBroadcastPacket {
        let decoder = JSONDecoder()
        return try decoder.decode(TransactionBroadcastPacket.self, from: data)
    }

    /// Increment hop count (for mesh propagation)
    mutating func incrementHopCount() {
        hopCount += 1
    }
}

// MARK: - Encrypted Payment Request Packet

/// Private payment request packet (sent via Noise encrypted channel)
struct PrivatePaymentRequestPacket: Codable {
    /// Payment request details
    let request: PaymentRequest

    /// Sender's public key
    let senderPublicKey: Data

    /// Request timestamp
    let timestamp: UInt64

    init(request: PaymentRequest, senderPublicKey: Data) {
        self.request = request
        self.senderPublicKey = senderPublicKey
        self.timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
    }

    /// Encode to binary data
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    /// Decode from binary data
    static func decode(from data: Data) throws -> PrivatePaymentRequestPacket {
        let decoder = JSONDecoder()
        return try decoder.decode(PrivatePaymentRequestPacket.self, from: data)
    }
}

/// Payment receipt packet (sent after successful payment)
struct PaymentReceiptPacket: Codable {
    /// Transaction ID of the payment
    let transactionId: String

    /// Recipient's address
    let recipientAddress: String

    /// Amount received
    let amount: UInt64

    /// Receipt timestamp
    let timestamp: UInt64

    /// Recipient's signature
    var signature: Data?

    init(transactionId: String, recipientAddress: String, amount: UInt64) {
        self.transactionId = transactionId
        self.recipientAddress = recipientAddress
        self.amount = amount
        self.timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        self.signature = nil
    }

    /// Encode to binary data
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    /// Decode from binary data
    static func decode(from data: Data) throws -> PaymentReceiptPacket {
        let decoder = JSONDecoder()
        return try decoder.decode(PaymentReceiptPacket.self, from: data)
    }
}
