//
//  BluetoothService.swift
//  RevEv
//

import Foundation
import CoreBluetooth
import Combine

/// Core Bluetooth management service for ELM327 adapters
final class BluetoothService: NSObject, ObservableObject {
    // MARK: - Published State

    @Published var connectionState: ConnectionState = .disconnected
    @Published private(set) var discoveredDevices: [BluetoothDevice] = []
    @Published private(set) var connectedDevice: BluetoothDevice?
    @Published var currentRPM: Int = 0

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var preferredWriteType: CBCharacteristicWriteType = .withResponse

    private var dataBuffer = Data()

    /// Continuation for async response waiting
    private var responseContinuation: CheckedContinuation<String, Error>?

    /// Auto-connect settings
    var isAutoConnectEnabled: Bool = true
    private let lastDeviceKey = "RevEv.LastConnectedDeviceUUID"

    // MARK: - Computed Properties

    var connectedDeviceName: String? {
        connectedDevice?.name
    }

    // MARK: - Initialization

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Auto-Connect

    /// Get the last connected device UUID
    private var lastConnectedDeviceUUID: UUID? {
        get {
            guard let uuidString = UserDefaults.standard.string(forKey: lastDeviceKey) else { return nil }
            return UUID(uuidString: uuidString)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: lastDeviceKey)
        }
    }

    /// Save the current device for auto-reconnect
    private func saveLastDevice(_ device: BluetoothDevice) {
        lastConnectedDeviceUUID = device.peripheral.identifier
        print("DEBUG: Saved device for auto-connect: \(device.name)")
    }

    /// Check if device matches last connected or is a known OBD adapter
    private func shouldAutoConnect(to device: BluetoothDevice) -> Bool {
        // Priority 1: Last connected device
        if let lastUUID = lastConnectedDeviceUUID, device.peripheral.identifier == lastUUID {
            print("DEBUG: Found last connected device: \(device.name)")
            return true
        }

        // Priority 2: Known OBD adapter names
        let name = device.name.lowercased()
        let isKnownOBD = name.contains("obd") ||
                         name.contains("elm") ||
                         name.contains("vlink") ||
                         name.contains("veepeak") ||
                         name.contains("ios-vlink")

        if isKnownOBD {
            print("DEBUG: Found known OBD adapter: \(device.name)")
            return true
        }

        return false
    }

    // MARK: - Public Methods

    /// Start auto-connect (try to connect to last known device)
    func startAutoConnect() {
        guard isAutoConnectEnabled else { return }
        startScanning()
    }

    /// Start scanning for ELM327 devices
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("DEBUG: Bluetooth not ready, state: \(centralManager.state.rawValue)")
            connectionState = .error("Bluetooth is not available")
            return
        }

        print("DEBUG: Starting scan...")
        discoveredDevices.removeAll()
        connectionState = .scanning

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.connectionState == .scanning {
                print("DEBUG: Scan timeout")
                self?.stopScanning()
            }
        }
    }

    /// Stop scanning for devices
    func stopScanning() {
        centralManager.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
    }

    /// Connect to a specific device
    func connect(to device: BluetoothDevice) {
        stopScanning()
        connectionState = .connecting
        centralManager.connect(device.peripheral, options: nil)
    }

    /// Disconnect from current device
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    /// Send a command and wait for response
    @MainActor
    func sendCommand(_ command: String, timeout: TimeInterval = 3.0) async throws -> String {
        guard let writeChar = writeCharacteristic,
              let peripheral = connectedPeripheral else {
            throw BluetoothError.notConnected
        }

        // Cancel any pending continuation to prevent "multiple resumes" crash
        if let pending = responseContinuation {
            pending.resume(throwing: BluetoothError.timeout)
            responseContinuation = nil
        }

        // Clear buffer before sending
        dataBuffer.removeAll()

        // Add carriage return to command
        let commandData = "\(command)\r".data(using: .ascii)!

        return try await withCheckedThrowingContinuation { continuation in
            self.responseContinuation = continuation

            peripheral.writeValue(commandData, for: writeChar, type: self.preferredWriteType)

            // Timeout handling
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self = self else { return }
                if self.responseContinuation != nil {
                    let bufferContent = String(data: self.dataBuffer, encoding: .ascii) ?? "NON-ASCII"
                    print("DEBUG: Command '\(command)' timed out after \(timeout)s. Buffer: [\(bufferContent)]")
                    self.responseContinuation?.resume(throwing: BluetoothError.timeout)
                    self.responseContinuation = nil
                }
            }
        }
    }

    // MARK: - Private Methods

    private func cleanup() {
        connectedPeripheral = nil
        connectedDevice = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        dataBuffer.removeAll()
        responseContinuation = nil
        connectionState = .disconnected
    }

    private func processReceivedData(_ data: Data) {
        dataBuffer.append(data)

        // Check for response terminator '>'
        guard let responseString = String(data: dataBuffer, encoding: .ascii) else {
            return
        }

        if responseString.contains(">") {
            // Some devices send multiple lines before the '>'
            // We want the whole response up to the '>'
            let response = responseString
                .replacingOccurrences(of: ">", with: "")

            dataBuffer.removeAll()

            if let continuation = responseContinuation {
                continuation.resume(returning: response)
                responseContinuation = nil
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("DEBUG: centralManagerDidUpdateState: \(central.state.rawValue)")

        switch central.state {
        case .poweredOn:
            print("DEBUG: Bluetooth powered on")
            // Auto-start scanning when Bluetooth is ready
            if isAutoConnectEnabled && connectionState == .disconnected {
                print("DEBUG: Bluetooth ready, starting auto-scan...")
                startScanning()
            }
        case .poweredOff:
            connectionState = .error("Bluetooth is turned off")
            cleanup()
        case .unauthorized:
            connectionState = .error("Bluetooth permission denied")
        case .unsupported:
            connectionState = .error("Bluetooth not supported")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Filter for likely OBD adapters by name
        let name = peripheral.name ?? ""
        let isLikelyOBD = name.lowercased().contains("obd") ||
                          name.lowercased().contains("elm") ||
                          name.lowercased().contains("vlink") ||
                          name.lowercased().contains("veepeak") ||
                          name.lowercased().contains("car") ||
                          name.contains("IOS-Vlink") ||
                          name.contains("OBDII")

        // Only add devices with names or likely OBD devices
        guard !name.isEmpty || isLikelyOBD else { return }

        let device = BluetoothDevice(peripheral: peripheral, rssi: RSSI.intValue)

        print("DEBUG: Discovered device: \(device.name) (RSSI: \(RSSI))")

        if !discoveredDevices.contains(where: { $0.id == device.id }) {
            discoveredDevices.append(device)

            // Auto-connect if enabled and device matches criteria
            if isAutoConnectEnabled &&
               connectionState == .scanning &&
               shouldAutoConnect(to: device) {
                print("DEBUG: Auto-connecting to \(device.name)...")
                connect(to: device)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("DEBUG: Connected to: \(peripheral.name ?? "Unknown")")
        connectedPeripheral = peripheral
        connectedDevice = discoveredDevices.first { $0.id == peripheral.identifier }
        peripheral.delegate = self
        connectionState = .connected

        // Save for auto-reconnect
        if let device = connectedDevice {
            saveLastDevice(device)
        }

        // Small delay to let BLE connection stabilize before service discovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            peripheral.discoverServices(nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("DEBUG: Failed to connect: \(error?.localizedDescription ?? "Unknown")")
        connectionState = .error(error?.localizedDescription ?? "Connection failed")
        cleanup()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("DEBUG: Disconnected from: \(peripheral.name ?? "Unknown"), error: \(error?.localizedDescription ?? "none")")
        cleanup()

        // Auto-reconnect after unexpected disconnect
        if isAutoConnectEnabled && error != nil {
            print("DEBUG: Connection lost, attempting auto-reconnect in 2s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.startScanning()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("DEBUG: Service discovery error: \(error.localizedDescription)")
            connectionState = .error("Failed to discover services")
            return
        }

        guard let services = peripheral.services else {
            print("DEBUG: No services found")
            return
        }

        print("DEBUG: Discovered \(services.count) services")
        for service in services {
            print("DEBUG:   - Service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("DEBUG: Characteristic discovery error: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            return
        }

        let knownWriteUUID = ELM327UUIDs.writeCharacteristic(for: service.uuid)
        let knownNotifyUUID = ELM327UUIDs.notifyCharacteristic(for: service.uuid)

        for characteristic in characteristics {
            print("DEBUG:     - Characteristic: \(characteristic.uuid), properties: \(characteristic.properties.rawValue)")

            // Check against known UUIDs first
            if let writeUUID = knownWriteUUID, characteristic.uuid == writeUUID {
                writeCharacteristic = characteristic
                preferredWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
                print("DEBUG: Found known write characteristic: \(characteristic.uuid)")
            } else if let notifyUUID = knownNotifyUUID, characteristic.uuid == notifyUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("DEBUG: Found known notify characteristic: \(characteristic.uuid)")
            }

            // Fallback to property-based discovery if not already found
            if writeCharacteristic == nil {
                if characteristic.properties.contains(.write) {
                    writeCharacteristic = characteristic
                    preferredWriteType = .withResponse
                    print("DEBUG: Found write characteristic by properties: \(characteristic.uuid)")
                } else if characteristic.properties.contains(.writeWithoutResponse) {
                    writeCharacteristic = characteristic
                    preferredWriteType = .withoutResponse
                    print("DEBUG: Found writeWithoutResponse characteristic: \(characteristic.uuid)")
                }
            }

            if notifyCharacteristic == nil && characteristic.properties.contains(.notify) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("DEBUG: Found notify characteristic by properties: \(characteristic.uuid)")
            }
        }

        // Check if we have both characteristics
        if writeCharacteristic != nil && notifyCharacteristic != nil {
            print("DEBUG: Both characteristics found. Ready for commands.")
            connectionState = .initializing
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            return
        }

        processReceivedData(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("DEBUG: Write error: \(error.localizedDescription)")
            responseContinuation?.resume(throwing: BluetoothError.writeFailed(error.localizedDescription))
            responseContinuation = nil
        }
    }
}

// MARK: - BluetoothDevice

/// Represents a discovered Bluetooth device
struct BluetoothDevice: Identifiable, Hashable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int

    init(peripheral: CBPeripheral, rssi: Int) {
        self.id = peripheral.identifier
        self.peripheral = peripheral
        self.name = peripheral.name ?? "Unknown Device"
        self.rssi = rssi
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: BluetoothDevice, rhs: BluetoothDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Errors

enum BluetoothError: LocalizedError {
    case notConnected
    case timeout
    case writeFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to device"
        case .timeout:
            return "Command timeout"
        case .writeFailed(let reason):
            return "Write failed: \(reason)"
        case .invalidResponse:
            return "Invalid response received"
        }
    }
}
