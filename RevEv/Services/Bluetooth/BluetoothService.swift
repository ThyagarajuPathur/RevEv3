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
    private var lastCommandTask: Task<String, Error>?

    private var isPolling = false
    private var reconnectTimer: Timer?

    private var useEVProtocol = true
    private var consecutiveTimeouts = 0
    private let maxTimeouts = 3
    private var pendingScan = false

    // UserDefaults keys
    private let lastDeviceUUIDKey = "lastConnectedDeviceUUID"

    // MARK: - Initialization

    override init() {
        super.init()
        print("BluetoothService init - creating CBCentralManager")
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public Methods

    /// Start scanning for OBD devices
    func startScanning() {
        print("startScanning() called, centralManager.state = \(centralManager.state.rawValue)")

        guard centralManager.state == .poweredOn else {
            print("Bluetooth not ready yet, queuing scan request...")
            pendingScan = true
            connectionState = .scanning  // Show scanning state in UI
            return
        }

        performScan()
    }

    private func performScan() {
        print("Starting Bluetooth scan...")
        pendingScan = false
        connectionState = .scanning
        discoveredDevices.removeAll()

        // Scan for all devices (we filter by name)
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            print("Scan timeout, stopping...")
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

    /// Send a command and wait for response (serialized)
    func sendCommand(_ command: String, timeout: TimeInterval = 5.0) async throws -> String {
        let previousTask = lastCommandTask
        let newTask = Task {
            _ = try? await previousTask?.value
            return try await sendCommandInternal(command, timeout: timeout)
        }
        lastCommandTask = newTask
        return try await newTask.value
    }

    private func sendCommandInternal(_ command: String, timeout: TimeInterval = 5.0) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            sendCommandInternal(command, timeout: timeout) { response in
                continuation.resume(returning: response)
            }
        }
    }

    private func sendCommandInternal(_ command: String, timeout: TimeInterval = 5.0, completion: @escaping (String) -> Void) {
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
        print("Initializing adapter...")
        connectionState = .initializing
        consecutiveTimeouts = 0

        for command in ATCommand.initSequence {
            print("Sending: \(command.trimmingCharacters(in: .whitespacesAndNewlines))")
            let response = try await sendCommand(command, timeout: command == ATCommand.reset ? 2.0 : 1.0)
            print("Response: \(response.trimmingCharacters(in: .whitespacesAndNewlines))")

            if command == ATCommand.reset {
                // Wait extra time after reset
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }

            if OBDResponse.isError(response) && command != ATCommand.reset {
                print("Initialization failed at: \(command)")
                throw BluetoothError.initializationFailed(command)
            }
        }

        print("Adapter initialized successfully")
        connectionState = .connected
        startPolling()
    }

    // MARK: - RPM Polling

    func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        
        Task {
            while isPolling {
                await pollRPM()
                try? await Task.sleep(nanoseconds: 70_000_000) // 70ms
            }
        }
    }

    func stopPolling() {
        isPolling = false
    }

    private func pollRPM() async {
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
        print("centralManagerDidUpdateState: \(central.state.rawValue)")

        switch central.state {
        case .poweredOn:
            print("Bluetooth powered on")
            // Execute pending scan if requested before Bluetooth was ready
            if pendingScan {
                performScan()
            } else if isAutoConnectEnabled {
                startAutoConnect()
            }
        case .poweredOff:
            print("Bluetooth powered off")
            pendingScan = false
            connectionState = .error("Bluetooth is off")
        case .unauthorized:
            print("Bluetooth unauthorized")
            pendingScan = false
            connectionState = .error("Bluetooth unauthorized")
        case .unsupported:
            print("Bluetooth unsupported")
            pendingScan = false
            connectionState = .error("Bluetooth unsupported")
        case .resetting:
            print("Bluetooth resetting")
        case .unknown:
            print("Bluetooth state unknown")
        @unknown default:
            print("Bluetooth unknown state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? "Unknown"
        print("Discovered device: \(deviceName) - \(peripheral.identifier)")

        // Filter by name
        guard OBDDeviceFilter.isOBDAdapter(name: peripheral.name) else {
            print("  -> Filtered out (not OBD adapter)")
            return
        }

        print("  -> Matches OBD filter, adding to list")

        // Add to discovered devices if not already present
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)

            // Auto-connect to first device if scanning for auto-connect
            if isAutoConnectEnabled && connectionState == .scanning {
                print("  -> Auto-connecting...")
                connect(to: peripheral)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to: \(peripheral.name ?? "Unknown")")
        saveLastConnectedDevice(peripheral)
        connectedDeviceName = peripheral.name
        connectionState = .connecting
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionState = .error(error?.localizedDescription ?? "Connection failed")
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from: \(peripheral.name ?? "Unknown"), error: \(error?.localizedDescription ?? "none")")
        connectionState = .disconnected
        connectedDeviceName = nil
        stopPolling()
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Service discovery error: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            print("No services found")
            return
        }

        print("Discovered \(services.count) services:")
        for service in services {
            print("  - Service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            let uuid = characteristic.uuid

            // Check for known write characteristics by UUID
            if uuid == OBDServiceUUID.veepeakWrite ||
               uuid == OBDServiceUUID.genericRW ||
               uuid == OBDServiceUUID.obdlinkWrite {
                writeCharacteristic = characteristic
                print("Found write characteristic: \(uuid)")
            }

            // Check for known notify characteristics by UUID
            if uuid == OBDServiceUUID.veepeakNotify ||
               uuid == OBDServiceUUID.genericRW {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("Found notify characteristic: \(uuid)")
            }

            // Fallback: check by properties if no known UUID matched
            if writeCharacteristic == nil &&
               (characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)) {
                writeCharacteristic = characteristic
                print("Found write characteristic by properties: \(uuid)")
            }

            if notifyCharacteristic == nil && characteristic.properties.contains(.notify) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("Found notify characteristic by properties: \(uuid)")
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
