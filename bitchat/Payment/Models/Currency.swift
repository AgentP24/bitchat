import Foundation

/// Represents a currency/asset type in MeshPay
struct Currency: Codable, Hashable, Identifiable {
    /// 4-byte currency code (e.g., "MTOK", "WBTC", "USDT")
    let code: String

    /// Human-readable name
    let name: String

    /// Symbol for display (e.g., "MT", "₿", "$")
    let symbol: String

    /// Number of decimal places (e.g., 8 for Bitcoin-like)
    let decimals: Int

    /// Minimum transaction amount in base units
    let minAmount: UInt64

    /// Default transaction fee in base units
    let defaultFee: UInt64

    /// Color for UI representation
    let colorHex: String

    /// Whether this currency supports atomic swaps
    let supportsSwaps: Bool

    /// Creation timestamp
    let createdAt: Date

    var id: String { code }

    init(
        code: String,
        name: String,
        symbol: String,
        decimals: Int,
        minAmount: UInt64 = 1,
        defaultFee: UInt64 = 1000,
        colorHex: String = "#007AFF",
        supportsSwaps: Bool = true,
        createdAt: Date = Date()
    ) {
        // Ensure code is exactly 4 bytes
        let truncated = String(code.prefix(4))
        self.code = truncated.padding(toLength: 4, withPad: " ", startingAt: 0)
        self.name = name
        self.symbol = symbol
        self.decimals = decimals
        self.minAmount = minAmount
        self.defaultFee = defaultFee
        self.colorHex = colorHex
        self.supportsSwaps = supportsSwaps
        self.createdAt = createdAt
    }

    /// Convert base units to human-readable amount
    func format(amount: UInt64) -> String {
        let divisor = pow(10.0, Double(decimals))
        let value = Double(amount) / divisor
        return String(format: "%.\(decimals)f \(symbol)", value)
    }

    /// Convert human-readable amount to base units
    func parseAmount(_ string: String) -> UInt64? {
        guard let value = Double(string) else { return nil }
        let multiplier = pow(10.0, Double(decimals))
        return UInt64(value * multiplier)
    }

    /// Validate currency code format
    static func isValidCode(_ code: String) -> Bool {
        return code.count == 4 && code.allSatisfy { $0.isASCII }
    }
}

// MARK: - Predefined Currencies

extension Currency {
    /// MeshToken - Native currency
    static let meshToken = Currency(
        code: "MTOK",
        name: "MeshToken",
        symbol: "MT",
        decimals: 8,
        defaultFee: 1000,
        colorHex: "#007AFF"
    )

    /// Wrapped Bitcoin
    static let wrappedBitcoin = Currency(
        code: "WBTC",
        name: "Wrapped Bitcoin",
        symbol: "₿",
        decimals: 8,
        defaultFee: 500,
        colorHex: "#F7931A"
    )

    /// Mesh Dollar (stablecoin)
    static let meshDollar = Currency(
        code: "MUSD",
        name: "MeshDollar",
        symbol: "$M",
        decimals: 6,
        defaultFee: 100,
        colorHex: "#2ECC71"
    )

    /// Mesh Euro
    static let meshEuro = Currency(
        code: "MEUR",
        name: "MeshEuro",
        symbol: "€M",
        decimals: 6,
        defaultFee: 100,
        colorHex: "#3498DB"
    )

    /// Get all default currencies
    static var defaults: [Currency] {
        [meshToken, wrappedBitcoin, meshDollar, meshEuro]
    }
}

/// Currency pair for exchange rates
struct CurrencyPair: Codable, Hashable {
    let base: String      // Base currency code
    let quote: String     // Quote currency code
    var rate: Double      // Exchange rate (how much quote per unit of base)
    var timestamp: Date   // When rate was last updated

    init(base: String, quote: String, rate: Double, timestamp: Date = Date()) {
        self.base = base
        self.quote = quote
        self.rate = rate
        self.timestamp = timestamp
    }

    /// Inverse pair
    var inverse: CurrencyPair {
        CurrencyPair(base: quote, quote: base, rate: 1.0 / rate, timestamp: timestamp)
    }

    /// Convert amount from base to quote currency
    func convert(amount: UInt64, baseDecimals: Int, quoteDecimals: Int) -> UInt64 {
        let baseValue = Double(amount) / pow(10.0, Double(baseDecimals))
        let quoteValue = baseValue * rate
        let quoteUnits = quoteValue * pow(10.0, Double(quoteDecimals))
        return UInt64(quoteUnits)
    }
}

/// Currency registry managing available currencies
class CurrencyRegistry: ObservableObject {
    @Published private(set) var currencies: [String: Currency] = [:]
    @Published private(set) var exchangeRates: [String: CurrencyPair] = [:]

    init() {
        // Register default currencies
        for currency in Currency.defaults {
            currencies[currency.code] = currency
        }

        // Set default exchange rates (mocked - would come from oracle)
        setExchangeRate(base: "MTOK", quote: "MUSD", rate: 0.01)  // 1 MT = $0.01
        setExchangeRate(base: "WBTC", quote: "MUSD", rate: 45000.0)  // 1 WBTC = $45,000
        setExchangeRate(base: "MUSD", quote: "MEUR", rate: 0.92)     // 1 USD = 0.92 EUR
    }

    /// Register a new currency
    func register(_ currency: Currency) {
        currencies[currency.code] = currency
    }

    /// Get currency by code
    func get(_ code: String) -> Currency? {
        currencies[code]
    }

    /// Set exchange rate between two currencies
    func setExchangeRate(base: String, quote: String, rate: Double) {
        let pair = CurrencyPair(base: base, quote: quote, rate: rate)
        let key = "\(base)/\(quote)"
        exchangeRates[key] = pair

        // Also store inverse
        let inverseKey = "\(quote)/\(base)"
        exchangeRates[inverseKey] = pair.inverse
    }

    /// Get exchange rate for a pair
    func getRate(base: String, quote: String) -> Double? {
        let key = "\(base)/\(quote)"
        return exchangeRates[key]?.rate
    }

    /// Convert amount between currencies
    func convert(
        amount: UInt64,
        from: String,
        to: String
    ) -> UInt64? {
        guard from != to,
              let baseCurrency = currencies[from],
              let quoteCurrency = currencies[to],
              let pair = exchangeRates["\(from)/\(to)"] else {
            return amount // Same currency or missing data
        }

        return pair.convert(
            amount: amount,
            baseDecimals: baseCurrency.decimals,
            quoteDecimals: quoteCurrency.decimals
        )
    }
}
