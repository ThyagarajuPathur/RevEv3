//
//  OBDProtocolService.swift
//  RevEv
//

import Foundation
import Combine

/// OBD-II protocol service for vehicle data communication
@MainActor
final class OBDProtocolService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var rpm: Int = 0
    @Published private(set) var speed: Int = 0
    @Published private(set) var isPolling = false
    @Published private(set) var isInitialized = false

    // MARK: - Dependencies

    let bluetoothService: BluetoothService
    private var commandQueue: OBDCommandQueue?

    // MARK: - Private Properties

    private var pollingTask: Task<Void, Never>?
    private var consecutiveTimeouts = 0
    private let maxConsecutiveTimeouts = 5

    // MARK: - Initialization

    init(bluetoothService: BluetoothService) {
        self.bluetoothService = bluetoothService
        self.commandQueue = OBDCommandQueue(bluetoothService: bluetoothService)
    }

    // MARK: - Public Methods

    /// Initialize the ELM327 adapter
    func initializeAdapter() async throws {
        guard let queue = commandQueue else {
            throw OBDError.notConnected
        }

        isInitialized = false
        bluetoothService.connectionState = .initializing

        do {
            // 1. Reset the adapter (Long timeout 5s)
            let resetResponse = try await queue.execute("AT Z", timeout: 5.0)
            print("DEBUG: ATZ Response: \(resetResponse)")

            // CRITICAL: Delay for adapter boot-up
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s

            // 2. Setup basics
            _ = try await queue.execute("AT E0") // Echo Off
            _ = try await queue.execute("AT L0") // Linefeeds Off

            // 3. Force CAN Protocol (ISO 15765-4 CAN 11/500)
            _ = try await queue.execute("AT SP 6")

            // 4. Force BMS Header (7E4) for EV motor RPM
            _ = try await queue.execute("AT SH 7E4")

            isInitialized = true
            bluetoothService.connectionState = .connected
            print("DEBUG: OBD Protocol Service Initialized (EV Mode - BMS 7E4)")
        } catch {
            print("DEBUG: Initialization failed: \(error)")
            throw error
        }
    }

    /// Start polling for RPM data
    func startPolling() {
        guard !isPolling else { return }
        isPolling = true

        pollingTask = Task {
            while isPolling {
                await pollData()
                // Delay between polls to prevent buffer overflow
                // 70ms = ~14Hz polling rate
                try? await Task.sleep(nanoseconds: 70_000_000)
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        isPolling = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Send a raw command
    func sendRawCommand(_ command: String) async throws -> String {
        guard let queue = commandQueue else {
            throw OBDError.notConnected
        }

        return try await queue.execute(command)
    }

    // MARK: - Private Methods

    private func pollData() async {
        guard let queue = commandQueue, isInitialized else { return }

        // 1. Request Motor RPM from BMS
        // Try both PID formats: 220101 (Ioniq 5/EV6) and 2101 (Kona/Niro)
        var rpmSuccess = false

        // First try 220101 (Ioniq 5 / EV6 format)
        do {
            let response = try await queue.execute("220101", timeout: 5.0)
            print("DEBUG: [220101] Raw response: \(response.prefix(100))...")
            if let result = OBDParser.parseEVLongRPMWithDebug(from: response) {
                let (parsedRPM, pid, offset) = result
                print("DEBUG: RPM=\(parsedRPM) from PID \(pid) at offset \(offset)")
                rpm = abs(parsedRPM) // Use absolute value (negative = regen)
                rpmSuccess = true
            }
        } catch {
            print("DEBUG: [220101] Error: \(error.localizedDescription)")
            if error.localizedDescription.contains("timeout") {
                handleTimeout()
            }
        }

        // If 220101 failed, try 2101 (Kona / Niro format)
        if !rpmSuccess {
            do {
                let response = try await queue.execute("2101", timeout: 5.0)
                print("DEBUG: [2101] Raw response: \(response.prefix(100))...")
                if let result = OBDParser.parseEVLongRPMWithDebug(from: response) {
                    let (parsedRPM, pid, offset) = result
                    print("DEBUG: RPM=\(parsedRPM) from PID \(pid) at offset \(offset)")
                    rpm = abs(parsedRPM)
                    rpmSuccess = true
                }
            } catch {
                print("DEBUG: [2101] Error: \(error.localizedDescription)")
                if error.localizedDescription.contains("timeout") {
                    handleTimeout()
                }
            }
        }

        // Reset timeout counter on success
        if rpmSuccess {
            consecutiveTimeouts = 0
        }
    }

    private func handleTimeout() {
        consecutiveTimeouts += 1
        print("DEBUG: Consecutive timeouts: \(consecutiveTimeouts)/\(maxConsecutiveTimeouts)")

        if consecutiveTimeouts >= maxConsecutiveTimeouts {
            print("DEBUG: Max timeouts reached. Triggering self-healing recovery...")
            consecutiveTimeouts = 0
            Task {
                // Wait before recovery to let adapter stabilize
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                try? await initializeAdapter()
            }
        }
    }
}

// MARK: - Errors

enum OBDError: LocalizedError {
    case notConnected
    case notInitialized
    case noData
    case parseError
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to OBD adapter"
        case .notInitialized:
            return "Adapter not initialized"
        case .noData:
            return "No data available"
        case .parseError:
            return "Failed to parse response"
        case .timeout:
            return "Request timeout"
        }
    }
}
