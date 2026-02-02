import Foundation

/// Connection state for Bluetooth OBD adapter
enum ConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case initializing
    case connected
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .scanning:
            return "Scanning..."
        case .connecting:
            return "Connecting..."
        case .initializing:
            return "Initializing..."
        case .connected:
            return "Connected"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Data received from OBD-II adapter
struct OBDData {
    var rpm: Int = 0
    var speed: Int = 0
    var timestamp: Date = Date()

    /// Calculate throttle position from RPM change rate
    static func calculateThrottle(currentRPM: Int, previousRPM: Int, deltaTime: TimeInterval) -> Double {
        guard deltaTime > 0 else { return 0 }

        let rpmDelta = Double(currentRPM - previousRPM)
        let rpmRate = rpmDelta / deltaTime

        // Map RPM rate of change to throttle (0-1)
        // Positive rate = accelerating, negative = decelerating
        let maxRate: Double = 3000 // RPM/second for full throttle
        let normalizedRate = rpmRate / maxRate

        return clamp(normalizedRate, 0, 1)
    }
}

/// RPM history for smoothing and throttle calculation
class RPMHistory {
    private var readings: [(rpm: Int, timestamp: Date)] = []
    private let maxReadings = 10

    /// Add a new RPM reading
    func add(rpm: Int) {
        readings.append((rpm, Date()))
        if readings.count > maxReadings {
            readings.removeFirst()
        }
    }

    /// Get smoothed RPM using exponential moving average
    func smoothedRPM(alpha: Double = 0.3) -> Int {
        guard !readings.isEmpty else { return 0 }

        var smoothed = Double(readings[0].rpm)
        for reading in readings.dropFirst() {
            smoothed = alpha * Double(reading.rpm) + (1 - alpha) * smoothed
        }
        return Int(smoothed)
    }

    /// Calculate throttle from RPM rate of change
    func calculateThrottle() -> Double {
        guard readings.count >= 2 else { return 0 }

        let recent = readings.suffix(5)
        guard let first = recent.first, let last = recent.last else { return 0 }

        let deltaTime = last.timestamp.timeIntervalSince(first.timestamp)
        guard deltaTime > 0 else { return 0 }

        let rpmDelta = Double(last.rpm - first.rpm)
        let rpmRate = rpmDelta / deltaTime

        // Map to throttle: positive rate = throttle on
        let maxRate: Double = 2000
        return clamp(rpmRate / maxRate, 0, 1)
    }

    /// Clear all readings
    func clear() {
        readings.removeAll()
    }
}
