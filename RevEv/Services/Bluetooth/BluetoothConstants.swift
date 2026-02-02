import CoreBluetooth

/// Bluetooth UUIDs for various ELM327 OBD-II adapters
enum OBDServiceUUID {
    /// Veepeak and generic adapters
    static let veepeak = CBUUID(string: "FFF0")
    static let veepeakWrite = CBUUID(string: "FFF2")
    static let veepeakNotify = CBUUID(string: "FFF1")

    /// Generic FFE0 adapters
    static let generic = CBUUID(string: "FFE0")
    static let genericRW = CBUUID(string: "FFE1")

    /// OBDLink adapters
    static let obdlink = CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2")
    static let obdlinkWrite = CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")

    /// All known service UUIDs
    static let allServices: [CBUUID] = [veepeak, generic, obdlink]
}

/// AT commands for ELM327 adapter initialization
enum ATCommand {
    /// Reset adapter (wait 1s after)
    static let reset = "AT Z\r"

    /// Echo off
    static let echoOff = "AT E0\r"

    /// Linefeeds off
    static let linefeedsOff = "AT L0\r"

    /// Set protocol: ISO 15765-4 CAN (11-bit, 500kbaud)
    static let setProtocol = "AT SP 6\r"

    /// Set header to BMS ECU for EV motor RPM
    static let setHeaderEV = "AT SH 7E4\r"

    /// Set header for standard OBD
    static let setHeaderStandard = "AT SH 7DF\r"

    /// All initialization commands in order
    static let initSequence: [String] = [
        reset,
        echoOff,
        linefeedsOff,
        setProtocol,
        setHeaderEV
    ]
}

/// OBD-II PID commands
enum OBDCommand {
    /// EV RPM (E-GMP platform: Hyundai Ioniq 5, Kia EV6)
    static let evRPM_EGMP = "220101\r"

    /// EV RPM (Older EVs: Kona EV, Niro EV)
    static let evRPM_Legacy = "2101\r"

    /// Standard engine RPM (ICE vehicles)
    static let standardRPM = "010C\r"

    /// Vehicle speed
    static let speed = "010D\r"
}

/// Device name filters for OBD adapters
enum OBDDeviceFilter {
    static let knownPrefixes = ["OBD", "ELM", "Veepeak", "Vlink", "OBDII", "Car", "V-LINK", "VGATE", "Konnwei", "Adapter"]

    /// Check if a device name matches known OBD adapter patterns
    static func isOBDAdapter(name: String?) -> Bool {
        guard let name = name?.uppercased() else { return false }
        return knownPrefixes.contains { name.contains($0.uppercased()) }
    }
}

/// Response markers
enum OBDResponse {
    /// Command prompt (response complete)
    static let prompt: Character = ">"

    /// Error responses
    static let errors = ["NO DATA", "UNABLE TO CONNECT", "ERROR", "?", "STOPPED", "BUS INIT"]

    /// Check if response indicates an error
    static func isError(_ response: String) -> Bool {
        let upper = response.uppercased()
        return errors.contains { upper.contains($0) }
    }
}
