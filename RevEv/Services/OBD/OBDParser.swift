//
//  OBDParser.swift
//  RevEv
//

import Foundation

/// Parser for OBD-II responses
enum OBDParser {
    /// Parse RPM response (PID 010C)
    /// Format: 41 0C XX YY where RPM = ((XX * 256) + YY) / 4
    static func parseRPM(from response: String) -> Int? {
        let bytes = extractBytes(from: response)

        // Find the 41 0C header
        guard let headerIndex = findHeader(bytes: bytes, header: [0x41, 0x0C]),
              headerIndex + 2 < bytes.count else {
            return nil
        }

        let a = Int(bytes[headerIndex])
        let b = Int(bytes[headerIndex + 1])

        return ((a * 256) + b) / 4
    }

    /// Parse Speed response (PID 010D)
    /// Format: 41 0D XX where Speed = XX km/h
    static func parseSpeed(from response: String) -> Int? {
        let bytes = extractBytes(from: response)

        // Find the 41 0D header
        guard let headerIndex = findHeader(bytes: bytes, header: [0x41, 0x0D]),
              headerIndex + 1 < bytes.count else {
            return nil
        }

        return Int(bytes[headerIndex])
    }

    /// Check if response indicates no data
    static func isNoData(_ response: String) -> Bool {
        let upper = response.uppercased()
        return upper.contains("NO DATA") ||
               upper.contains("UNABLE TO CONNECT") ||
               upper.contains("ERROR") ||
               upper.contains("?")
    }

    /// Check if response indicates successful initialization
    static func isOK(_ response: String) -> Bool {
        response.uppercased().contains("OK")
    }

    /// Check if response is ELM327 identifier
    static func isELM(_ response: String) -> Bool {
        response.uppercased().contains("ELM")
    }

    // MARK: - Private Helpers

    /// Extract hex bytes from response string
    /// Extract bytes from an OBD-II response string, handling multi-line formats
    private static func extractBytes(from response: String) -> [UInt8] {
        var bytes: [UInt8] = []

        // Split by lines and process each line
        let lines = response.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if trimmed.isEmpty || trimmed == ">" { continue }

            // Remove line prefix if present (e.g., "0:", "1:")
            var dataPart = trimmed
            if let colonIndex = trimmed.firstIndex(of: ":") {
                dataPart = String(trimmed[trimmed.index(after: colonIndex)...])
            } else if trimmed.count <= 3 {
                // Likely a length header (e.g. "03E") - skip it
                continue
            }

            // Clean the data part of any non-hex characters
            let hexOnly = dataPart.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()

            // Convert pairs to bytes
            var index = hexOnly.startIndex
            while index < hexOnly.endIndex {
                let nextIndex = hexOnly.index(index, offsetBy: 2, limitedBy: hexOnly.endIndex) ?? hexOnly.endIndex
                let pair = hexOnly[index..<nextIndex]
                if pair.count == 2, let byte = UInt8(pair, radix: 16) {
                    bytes.append(byte)
                }
                index = nextIndex
            }
        }

        return bytes
    }

    /// Parse long EV BMS responses (e.g., 220101 or 2101) to find Motor RPM
    /// Returns tuple of (rpm, pidUsed, offset) for debugging, or nil if parsing failed
    static func parseEVLongRPM(from response: String, debug: Bool = false) -> Int? {
        let result = parseEVLongRPMWithDebug(from: response)
        if debug, let (rpm, pid, offset) = result {
            print("DEBUG RPM: Found \(rpm) rpm using PID \(pid) at offset \(offset)")
        }
        return result?.0
    }

    /// Data offset for Motor RPM in 220101 response (E-GMP platform)
    /// Offset 53-54: Signed 16-bit motor RPM (-10100 to 10100)
    /// Negative = regenerative braking, Positive = driving
    private static let rpmOffset: Int = 53

    /// Parse with full debug info - returns (rpm, pidUsed, offset)
    static func parseEVLongRPMWithDebug(from response: String) -> (Int, String, Int)? {
        let bytes = extractBytes(from: response)

        // E-GMP platform (Ioniq 5, EV6, etc): 220101 -> response header 62 01 01
        if let headerIndex = findHeader(bytes: bytes, header: [0x62, 0x01, 0x01]) {
            let dataBytes = Array(bytes.dropFirst(headerIndex))

            if dataBytes.count > rpmOffset + 1 {
                let a = dataBytes[rpmOffset]
                let b = dataBytes[rpmOffset + 1]

                // Signed 16-bit: negative for regen, positive for driving
                let rpm = Int(Int16(bitPattern: UInt16(a) << 8 | UInt16(b)))
                return (rpm, "220101", rpmOffset)
            }
        }

        // Try Kona EV / Niro EV format: 2101 -> response header 61 01, offset 53-54
        if let headerIndex = findHeader(bytes: bytes, header: [0x61, 0x01]) {
            let offset = 53
            if bytes.count > headerIndex + offset + 1 {
                let a = bytes[headerIndex + offset]
                let b = bytes[headerIndex + offset + 1]
                let raw = Int16(bitPattern: UInt16(a) << 8 | UInt16(b))
                print("DEBUG: [2101] Header at \(headerIndex), bytes[\(headerIndex + offset)]=\(String(format: "0x%02X", a)), bytes[\(headerIndex + offset + 1)]=\(String(format: "0x%02X", b)), raw=\(raw)")
                return (Int(raw), "2101", offset)
            }
        }

        print("DEBUG: No valid RPM header found. Total bytes: \(bytes.count)")
        if !bytes.isEmpty {
            print("DEBUG: First 10 bytes: \(bytes.prefix(10).map { String(format: "0x%02X", $0) }.joined(separator: " "))")
        }

        return nil
    }

    /// Find header bytes in response and return the index of the first data byte
    private static func findHeader(bytes: [UInt8], header: [UInt8]) -> Int? {
        guard bytes.count >= header.count else { return nil }

        for i in 0...(bytes.count - header.count) {
            var match = true
            for j in 0..<header.count {
                if bytes[i + j] != header[j] {
                    match = false
                    break
                }
            }
            if match {
                return i + header.count
            }
        }

        return nil
    }
}
