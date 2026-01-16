import Foundation

/// Represents a MeshPay wallet containing payment identity and balance
struct Wallet: Codable, Identifiable {
    /// Wallet identifier (derived from payment address)
    var id: String { identity.address }

    /// Payment identity (keys and address)
    let identity: PaymentIdentity

    /// Human-readable label for this wallet
    var label: String

    /// When this wallet was created
    let createdAt: Date

    /// Is this the default wallet for payments
    var isDefault: Bool

    /// Optional metadata
    var metadata: [String: String]

    /// Memberwise initializer
    init(
        identity: PaymentIdentity,
        label: String,
        createdAt: Date = Date(),
        isDefault: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.identity = identity
        self.label = label
        self.createdAt = createdAt
        self.isDefault = isDefault
        self.metadata = metadata
    }

    /// Create a new wallet with generated keys
    static func generate(label: String = "Default Wallet") throws -> Wallet {
        let identity = try PaymentIdentity.generate()
        return Wallet(identity: identity, label: label, isDefault: true)
    }

    /// Import wallet from private key
    static func importFromPrivateKey(_ privateKey: Data, label: String) throws -> Wallet {
        let identity = try PaymentIdentity(privateKeyData: privateKey)
        return Wallet(identity: identity, label: label)
    }
}

/// Wallet balance information
struct WalletBalance: Codable {
    /// Total confirmed balance in units
    let confirmed: UInt64

    /// Pending balance (unconfirmed transactions)
    let pending: UInt64

    /// Total spendable balance
    var total: UInt64 {
        confirmed + pending
    }

    /// Number of UTXOs
    let utxoCount: Int

    /// Balance in human-readable tokens
    var confirmedTokens: Double {
        Double(confirmed) / 100_000_000.0
    }

    var pendingTokens: Double {
        Double(pending) / 100_000_000.0
    }

    var totalTokens: Double {
        Double(total) / 100_000_000.0
    }

    init(confirmed: UInt64, pending: UInt64, utxoCount: Int) {
        self.confirmed = confirmed
        self.pending = pending
        self.utxoCount = utxoCount
    }

    static var zero: WalletBalance {
        WalletBalance(confirmed: 0, pending: 0, utxoCount: 0)
    }
}

/// Payment request that can be shared via QR code
struct PaymentRequest: Codable {
    /// Recipient's payment address
    let address: String

    /// Requested amount in units
    let amount: UInt64

    /// Optional label/description
    var label: String?

    /// Optional message
    var message: String?

    /// When this request was created
    let createdAt: Date

    /// Expiration time (optional)
    var expiresAt: Date?

    /// Unique request ID
    let id: String

    init(
        address: String,
        amount: UInt64,
        label: String? = nil,
        message: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.address = address
        self.amount = amount
        self.label = label
        self.message = message
        self.createdAt = Date()
        self.expiresAt = expiresAt
        self.id = UUID().uuidString
    }

    /// Convert to QR-codeable string
    func toQRString() -> String {
        var components = ["meshpay:\(address)"]

        if amount > 0 {
            components.append("amount=\(amount)")
        }
        if let label = label {
            components.append("label=\(label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }
        if let message = message {
            components.append("message=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        }

        let query = components.dropFirst().joined(separator: "&")
        return query.isEmpty ? components[0] : "\(components[0])?\(query)"
    }

    /// Parse from QR-codeable string
    static func fromQRString(_ string: String) -> PaymentRequest? {
        guard string.hasPrefix("meshpay:") else { return nil }

        let parts = string.dropFirst(8).components(separatedBy: "?")
        let address = String(parts[0])

        var amount: UInt64 = 0
        var label: String?
        var message: String?

        if parts.count > 1 {
            let params = parts[1].components(separatedBy: "&")
            for param in params {
                let kv = param.components(separatedBy: "=")
                guard kv.count == 2 else { continue }

                switch kv[0] {
                case "amount":
                    amount = UInt64(kv[1]) ?? 0
                case "label":
                    label = kv[1].removingPercentEncoding
                case "message":
                    message = kv[1].removingPercentEncoding
                default:
                    break
                }
            }
        }

        return PaymentRequest(address: address, amount: amount, label: label, message: message)
    }

    /// Check if request has expired
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }

    /// Amount in tokens
    var amountInTokens: Double {
        Double(amount) / 100_000_000.0
    }
}
