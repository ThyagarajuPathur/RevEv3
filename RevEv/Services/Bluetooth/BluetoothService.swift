import CoreBluetooth
import Combine

/// Bluetooth service for OBD-II adapter communication
class BluetoothService: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var connectionState: ConnectionState = .disconnected
    @Published var currentRPM: Int = 0
    @Published var currentSpeed: Int = 0
    @Published var isAutoConnectEnabled: Bool = true
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDeviceName: String?

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var responseBuffer = ""
    private var commandQueue: [String] = []
    private var isProcessingCommand = false
    private var commandCompletion: ((String) -> Void)?
    private var commandTimer: Timer?

    private var pollingTimer: Timer?
    private var reconnectTimer: Timer?

    private var useEVProtocol = true
    private var consecutiveTimeouts = 0
    private let maxTimeouts = 3

    // UserDefaults keys
    private let lastDeviceUUIDKey = "lastConnectedDeviceUUID"

    // MARK: - Initialization

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public Methods

    /// Start scanning for OBD devices
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionState = .error("Bluetooth not available")
            return
        }

        connectionState = .scanning
        discoveredDevices.removeAll()

        // Scan for all devices (we filter by name)
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopScanning()
        }
    }

    /// Stop scanning
    func stopScanning() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    /// Connect to a specific peripheral
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectionState = .connecting
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    /// Disconnect from current peripheral
    func disconnect() {
        stopPolling()
        reconnectTimer?.invalidate()

        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectionState = .disconnected
        connectedDeviceName = nil
    }

    /// Start auto-connect (try to connect to last known device)
    func startAutoConnect() {
        guard isAutoConnectEnabled else { return }
        guard centralManager.state == .poweredOn else { return }

        if let uuidString = UserDefaults.standard.string(forKey: lastDeviceUUIDKey),
           let uuid = UUID(uuidString: uuidString) {
            // Try to retrieve known peripheral
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = peripherals.first {
                connect(to: peripheral)
                return
            }
        }

        // Otherwise, scan and connect to first OBD device found
        startScanning()
    }

    /// Send a command and wait for response
    func sendCommand(_ command: String, timeout: TimeInterval = 5.0) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            sendCommand(command, timeout: timeout) { response in
                continuation.resume(returning: response)
            }
        }
    }

    private func sendCommand(_ command: String, timeout: TimeInterval = 5.0, completion: @escaping (String) -> Void) {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedPeripheral else {
            completion("")
            return
        }

        responseBuffer = ""
        commandCompletion = completion

        // Set timeout
        commandTimer?.invalidate()
        commandTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.handleCommandTimeout()
        }

        // Write command
        if let data = command.data(using: .ascii) {
            let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
                ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: characteristic, type: writeType)
        }
    }

    private func handleCommandTimeout() {
        consecutiveTimeouts += 1
        commandCompletion?("")
        commandCompletion = nil

        if consecutiveTimeouts >= maxTimeouts {
            // Re-initialize adapter
            Task {
                try? await initializeAdapter()
            }
        }
    }

    // MARK: - Adapter Initialization

    /// Initialize ELM327 adapter with AT commands
    func initializeAdapter() async throws {
        connectionState = .initializing
        consecutiveTimeouts = 0

        for command in ATCommand.initSequence {
            let response = try await sendCommand(command, timeout: command == ATCommand.reset ? 2.0 : 1.0)

            if command == ATCommand.reset {
                // Wait extra time after reset
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }

            if OBDResponse.isError(response) && command != ATCommand.reset {
                throw BluetoothError.initializationFailed(command)
            }
        }

        connectionState = .connected
        startPolling()
    }

    // MARK: - RPM Polling

    func startPolling() {
        stopPolling()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.pollRPM()
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func pollRPM() {
        Task {
            let command = useEVProtocol ? OBDCommand.evRPM_EGMP : OBDCommand.standardRPM

            do {
                let response = try await sendCommand(command)

                if OBDResponse.isError(response) {
                    // Try alternate protocol
                    if useEVProtocol {
                        let legacyResponse = try await sendCommand(OBDCommand.evRPM_Legacy)
                        if let rpm = OBDParser.parseEVRPM(from: legacyResponse) {
                            await MainActor.run {
                                self.currentRPM = rpm
                                self.consecutiveTimeouts = 0
                            }
                            return
                        }
                    }
                    return
                }

                // Parse RPM
                let rpm: Int?
                if useEVProtocol {
                    rpm = OBDParser.parseEVRPM(from: response)
                } else {
                    rpm = OBDParser.parseStandardRPM(from: response)
                }

                if let rpm = rpm {
                    await MainActor.run {
                        self.currentRPM = rpm
                        self.consecutiveTimeouts = 0
                    }
                }
            } catch {
                print("Polling error: \(error)")
            }
        }
    }

    // MARK: - Auto-Reconnect

    private func scheduleReconnect() {
        guard isAutoConnectEnabled else { return }

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.startAutoConnect()
        }
    }

    private func saveLastConnectedDevice(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastDeviceUUIDKey)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if isAutoConnectEnabled {
                startAutoConnect()
            }
        case .poweredOff:
            connectionState = .error("Bluetooth is off")
        case .unauthorized:
            connectionState = .error("Bluetooth unauthorized")
        case .unsupported:
            connectionState = .error("Bluetooth unsupported")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Filter by name
        guard OBDDeviceFilter.isOBDAdapter(name: peripheral.name) else { return }

        // Add to discovered devices if not already present
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)

            // Auto-connect to first device if scanning for auto-connect
            if isAutoConnectEnabled && connectionState == .scanning {
                connect(to: peripheral)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        saveLastConnectedDevice(peripheral)
        connectedDeviceName = peripheral.name
        connectionState = .connecting
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .error(error?.localizedDescription ?? "Connection failed")
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        connectedDeviceName = nil
        stopPolling()
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            // Check for write characteristic
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
            }

            // Check for notify characteristic
            if characteristic.properties.contains(.notify) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }

            // Some adapters use same characteristic for read/write
            if characteristic.uuid == OBDServiceUUID.genericRW {
                writeCharacteristic = characteristic
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        // If we have both characteristics, initialize
        if writeCharacteristic != nil && notifyCharacteristic != nil {
            Task {
                try? await initializeAdapter()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value,
              let string = String(data: data, encoding: .ascii) else { return }

        responseBuffer += string

        // Check for response terminator
        if responseBuffer.contains(OBDResponse.prompt) {
            commandTimer?.invalidate()
            let response = responseBuffer
            responseBuffer = ""
            commandCompletion?(response)
            commandCompletion = nil
        }
    }
}

// MARK: - Errors

enum BluetoothError: Error, LocalizedError {
    case notConnected
    case initializationFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to OBD adapter"
        case .initializationFailed(let command):
            return "Initialization failed at: \(command)"
        case .timeout:
            return "Command timeout"
        }
    }
}
