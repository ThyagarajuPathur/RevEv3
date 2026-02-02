import Foundation

/// Parser for OBD-II responses
struct OBDParser {

    // MARK: - EV RPM Parsing

    /// Parse EV motor RPM from 220101 response
    /// Response format: 62 01 01 [data...] where RPM is at bytes 53-54
    static func parseEVRPM(from response: String) -> Int? {
        let bytes = extractHexBytes(from: response)

        // Find header: 62 01 01
        guard let headerIndex = findHeader(bytes, header: [0x62, 0x01, 0x01]) else {
            // Try legacy header: 61 01
            if let legacyIndex = findHeader(bytes, header: [0x61, 0x01]) {
                return parseRPMAtOffset(bytes, headerIndex: legacyIndex, offset: 53)
            }
            return nil
        }

        return parseRPMAtOffset(bytes, headerIndex: headerIndex, offset: 53)
    }

    /// Parse RPM from bytes at given offset after header
    private static func parseRPMAtOffset(_ bytes: [UInt8], headerIndex: Int, offset: Int) -> Int? {
        let rpmIndex = headerIndex + offset

        guard bytes.count > rpmIndex + 1 else {
            return nil
        }

        let a = bytes[rpmIndex]
        let b = bytes[rpmIndex + 1]

        // Signed 16-bit big-endian
        let rawValue = Int16(bitPattern: UInt16(a) << 8 | UInt16(b))

        // Return absolute value (negative = regenerative braking)
        return abs(Int(rawValue))
    }

    // MARK: - Standard OBD RPM Parsing

    /// Parse standard engine RPM from 010C response
    /// Response format: 41 0C XX YY, RPM = ((XX * 256) + YY) / 4
    static func parseStandardRPM(from response: String) -> Int? {
        let bytes = extractHexBytes(from: response)

        // Find header: 41 0C
        guard let headerIndex = findHeader(bytes, header: [0x41, 0x0C]) else {
            return nil
        }

        let dataIndex = headerIndex + 2
        guard bytes.count > dataIndex + 1 else {
            return nil
        }

        let a = Int(bytes[dataIndex])
        let b = Int(bytes[dataIndex + 1])

        return ((a * 256) + b) / 4
    }

    // MARK: - Speed Parsing

    /// Parse vehicle speed from 010D response
    /// Response format: 41 0D XX, Speed = XX km/h
    static func parseSpeed(from response: String) -> Int? {
        let bytes = extractHexBytes(from: response)

        guard let headerIndex = findHeader(bytes, header: [0x41, 0x0D]) else {
            return nil
        }

        let dataIndex = headerIndex + 2
        guard bytes.count > dataIndex else {
            return nil
        }

        return Int(bytes[dataIndex])
    }

    // MARK: - Utility Functions

    /// Extract hex bytes from OBD response string
    /// Handles multi-line responses with line prefixes like "0:", "1:"
    static func extractHexBytes(from response: String) -> [UInt8] {
        var bytes: [UInt8] = []

        // Split by newlines and process each line
        let lines = response.components(separatedBy: .newlines)

        for line in lines {
            var cleanLine = line.trimmingCharacters(in: .whitespaces)

            // Remove line prefixes (0:, 1:, 2:, etc.)
            if let colonIndex = cleanLine.firstIndex(of: ":") {
                let prefixEndIndex = cleanLine.index(after: colonIndex)
                cleanLine = String(cleanLine[prefixEndIndex...]).trimmingCharacters(in: .whitespaces)
            }

            // Remove spaces and parse hex pairs
            let hexString = cleanLine.replacingOccurrences(of: " ", with: "")
            bytes.append(contentsOf: parseHexString(hexString))
        }

        return bytes
    }

    /// Parse a hex string into bytes
    private static func parseHexString(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let byteString = String(hex[index..<nextIndex])

            if let byte = UInt8(byteString, radix: 16) {
                bytes.append(byte)
            }

            index = nextIndex
        }

        return bytes
    }

    /// Find header bytes in data array
    private static func findHeader(_ bytes: [UInt8], header: [UInt8]) -> Int? {
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
                return i
            }
        }

        return nil
    }
}
