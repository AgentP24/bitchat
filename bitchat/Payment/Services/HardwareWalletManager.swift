import Foundation
import CoreBluetooth
import Combine
import BitLogger

/// Manages BLE connections to hardware wallets (Ledger, Trezor, etc.)
@MainActor
class HardwareWalletManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    /// Connected hardware wallets
    @Published private(set) var connectedDevices: [HardwareWallet] = []

    /// Available (discovered) devices
    @Published private(set) var availableDevices: [HardwareWallet] = []

    /// Current connection state
    @Published private(set) var connectionState: ConnectionState = .disconnected

    /// Last error
    @Published private(set) var lastError: HardwareWalletError?

    // MARK: - Private Properties

    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [CBPeripheral] = []
    private var activePeripheral: CBPeripheral?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Constants

    /// Ledger Nano X service UUID
    private let ledgerServiceUUID = CBUUID(string: "13D63400-2C97-0004-0000-4C6564676572")

    /// Minimum value for hardware wallet enforcement (0.1 MT)
    private let hardwareThreshold: UInt64 = 10_000_000

    // MARK: - Initialization

    override init() {
        super.init()
        setupBluetooth()
    }

    private func setupBluetooth() {
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Device Discovery

    /// Start scanning for hardware wallets
    func startScanning() {
        guard centralManager?.state == .poweredOn else {
            lastError = .bluetoothPoweredOff
            return
        }

        availableDevices = []
        centralManager?.scanForPeripherals(
            withServices: [ledgerServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        SecureLogger.info("🔍 Scanning for hardware wallets...", category: .session)
    }

    /// Stop scanning
    func stopScanning() {
        centralManager?.stopScan()
        SecureLogger.info("⏹️ Stopped scanning for hardware wallets", category: .session)
    }

    // MARK: - Connection Management

    /// Connect to a hardware wallet
    func connect(to device: HardwareWallet) {
        guard let peripheral = discoveredPeripherals.first(where: { $0.identifier == device.id }) else {
            lastError = .deviceNotFound
            return
        }

        connectionState = .connecting
        activePeripheral = peripheral
        centralManager?.connect(peripheral, options: nil)
    }

    /// Disconnect from current device
    func disconnect() {
        if let peripheral = activePeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectionState = .disconnected
        activePeripheral = nil
    }

    // MARK: - Transaction Signing

    /// Sign a transaction using hardware wallet
    func signTransaction(
        _ transaction: Transaction,
        with device: HardwareWallet
    ) async throws -> Transaction {
        guard connectedDevices.contains(where: { $0.id == device.id }) else {
            throw HardwareWalletError.deviceNotConnected
        }

        // Serialize unsigned transaction
        let unsignedData = transaction.dataToSign()

        SecureLogger.info("📝 Requesting signature from hardware wallet...", category: .session)

        // Send to hardware wallet for signing
        // In production, this would use APDU commands specific to the device
        let signature = try await sendSigningRequest(unsignedData, to: device)

        // Create signed transaction
        var signedTx = transaction
        signedTx.signature = signature

        SecureLogger.info("✅ Transaction signed by hardware wallet", category: .session)
        return signedTx
    }

    /// Send signing request to hardware wallet (mock implementation)
    private func sendSigningRequest(_ data: Data, to device: HardwareWallet) async throws -> Data {
        // In production, this would:
        // 1. Construct APDU command for device
        // 2. Send via BLE characteristic
        // 3. Wait for user confirmation on device
        // 4. Receive signed data
        // 5. Parse and return signature

        // Mock delay for user confirmation
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Mock signature (in production, this comes from the hardware)
        // For now, return empty signature to indicate hardware signing was attempted
        return Data(repeating: 0, count: 64)
    }

    /// Check if transaction requires hardware wallet
    func requiresHardwareWallet(_ transaction: Transaction) -> Bool {
        let totalAmount = transaction.totalOutputAmount()
        return totalAmount >= hardwareThreshold
    }

    // MARK: - Key Derivation

    /// Get address from hardware wallet using BIP-44 derivation path
    func deriveAddress(
        from device: HardwareWallet,
        coinType: UInt32 = 0,
        account: UInt32 = 0,
        change: UInt32 = 0,
        addressIndex: UInt32 = 0
    ) async throws -> String {
        guard connectedDevices.contains(where: { $0.id == device.id }) else {
            throw HardwareWalletError.deviceNotConnected
        }

        // BIP-44 path: m/44'/coin_type'/account'/change/address_index
        let path = "m/44'/\(coinType)'/\(account)'/\(change)/\(addressIndex)"

        SecureLogger.info("🔑 Deriving address from hardware: \(path)", category: .session)

        // In production: Send derivation command to device
        // Mock: Return placeholder address
        try await Task.sleep(nanoseconds: 1_000_000_000)

        return "M\(device.id.uuidString.prefix(40))"
    }

    // MARK: - Device Management

    /// Verify device fingerprint (OOB verification)
    func verifyFingerprint(_ fingerprint: String, for device: HardwareWallet) -> Bool {
        // Compare displayed fingerprint on device with app
        // User must manually verify they match
        return device.fingerprint == fingerprint
    }

    /// Pair device with app
    func pair(_ device: HardwareWallet, fingerprint: String) throws {
        guard verifyFingerprint(fingerprint, for: device) else {
            throw HardwareWalletError.fingerprintMismatch
        }

        // Store paired device (in production, save to keychain)
        if !connectedDevices.contains(where: { $0.id == device.id }) {
            connectedDevices.append(device)
        }

        SecureLogger.info("🤝 Hardware wallet paired: \(device.name)", category: .session)
    }
}

// MARK: - CBCentralManagerDelegate

@MainActor
extension HardwareWalletManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            SecureLogger.info("✅ Bluetooth powered on", category: .session)
        case .poweredOff:
            lastError = .bluetoothPoweredOff
            SecureLogger.warning("⚠️ Bluetooth powered off", category: .session)
        case .unauthorized:
            lastError = .bluetoothUnauthorized
            SecureLogger.error("❌ Bluetooth unauthorized", category: .session)
        case .unsupported:
            lastError = .bluetoothUnsupported
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Create hardware wallet object
        let deviceName = peripheral.name ?? "Unknown Device"
        let device = HardwareWallet(
            id: peripheral.identifier,
            name: deviceName,
            type: .ledgerNanoX,
            firmwareVersion: "Unknown",
            fingerprint: peripheral.identifier.uuidString
        )

        if !availableDevices.contains(where: { $0.id == device.id }) {
            availableDevices.append(device)
            discoveredPeripherals.append(peripheral)
            SecureLogger.info("📱 Discovered hardware wallet: \(deviceName)", category: .session)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        SecureLogger.info("✅ Connected to hardware wallet", category: .session)

        // Discover services
        peripheral.delegate = self
        peripheral.discoverServices([ledgerServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        lastError = .connectionFailed
        SecureLogger.error("❌ Failed to connect: \(error?.localizedDescription ?? "unknown")", category: .session)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        activePeripheral = nil
        SecureLogger.info("📡 Disconnected from hardware wallet", category: .session)
    }
}

// MARK: - CBPeripheralDelegate

@MainActor
extension HardwareWalletManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            lastError = .serviceDiscoveryFailed
            return
        }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            lastError = .characteristicDiscoveryFailed
            return
        }

        SecureLogger.info("✅ Hardware wallet ready for signing", category: .session)
    }
}

// MARK: - Supporting Types

/// Represents a hardware wallet device
struct HardwareWallet: Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: WalletType
    let firmwareVersion: String
    let fingerprint: String // For OOB verification
    var isPaired: Bool = false

    static func == (lhs: HardwareWallet, rhs: HardwareWallet) -> Bool {
        lhs.id == rhs.id
    }
}

/// Supported hardware wallet types
enum WalletType: String, Codable {
    case ledgerNanoX = "Ledger Nano X"
    case ledgerNanoS = "Ledger Nano S Plus"
    case trezorT = "Trezor Model T"
    case genericBLE = "Generic BLE Wallet"
}

/// Connection state
enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case error
}

/// Hardware wallet errors
enum HardwareWalletError: LocalizedError {
    case deviceNotFound
    case deviceNotConnected
    case bluetoothPoweredOff
    case bluetoothUnauthorized
    case bluetoothUnsupported
    case connectionFailed
    case serviceDiscoveryFailed
    case characteristicDiscoveryFailed
    case signingFailed
    case fingerprintMismatch
    case userRejected

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Hardware wallet not found"
        case .deviceNotConnected:
            return "Hardware wallet not connected"
        case .bluetoothPoweredOff:
            return "Bluetooth is powered off"
        case .bluetoothUnauthorized:
            return "Bluetooth access not authorized"
        case .bluetoothUnsupported:
            return "Bluetooth not supported on this device"
        case .connectionFailed:
            return "Failed to connect to hardware wallet"
        case .serviceDiscoveryFailed:
            return "Failed to discover wallet services"
        case .characteristicDiscoveryFailed:
            return "Failed to discover wallet characteristics"
        case .signingFailed:
            return "Transaction signing failed"
        case .fingerprintMismatch:
            return "Device fingerprint does not match"
        case .userRejected:
            return "User rejected transaction on device"
        }
    }
}
