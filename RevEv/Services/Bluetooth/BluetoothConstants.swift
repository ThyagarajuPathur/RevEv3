//
//  BluetoothConstants.swift
//  RevEv
//

import Foundation
import CoreBluetooth

/// Known ELM327 Bluetooth LE UUIDs for various adapter manufacturers
enum ELM327UUIDs {
    /// Veepeak/Generic adapters
    static let serviceVeepeak = CBUUID(string: "FFF0")
    static let writeVeepeak = CBUUID(string: "FFF2")
    static let notifyVeepeak = CBUUID(string: "FFF1")

    /// Alternative generic adapters
    static let serviceFFE0 = CBUUID(string: "FFE0")
    static let characteristicFFE1 = CBUUID(string: "FFE1")

    /// OBDLink adapters
    static let serviceOBDLink = CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2")
    static let writeOBDLink = CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")
    static let notifyOBDLink = CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2")

    /// All known service UUIDs to scan for
    static let allServiceUUIDs: [CBUUID] = [
        serviceVeepeak,
        serviceFFE0,
        serviceOBDLink
    ]

    /// Map service UUID to write characteristic UUID
    static func writeCharacteristic(for service: CBUUID) -> CBUUID? {
        switch service {
        case serviceVeepeak:
            return writeVeepeak
        case serviceFFE0:
            return characteristicFFE1
        case serviceOBDLink:
            return writeOBDLink
        default:
            return nil
        }
    }

    /// Map service UUID to notify characteristic UUID
    static func notifyCharacteristic(for service: CBUUID) -> CBUUID? {
        switch service {
        case serviceVeepeak:
            return notifyVeepeak
        case serviceFFE0:
            return characteristicFFE1
        case serviceOBDLink:
            return notifyOBDLink
        default:
            return nil
        }
    }
}

/// ELM327 AT commands for initialization
enum ELM327Commands {
    static let reset = "ATZ"
    static let echoOff = "ATE0"
    static let linefeedsOff = "ATL0"
    static let spacesOff = "ATS0"
    static let autoProtocol = "ATSP0"
    static let headersOff = "ATH0"
    static let adaptiveTiming = "ATAT1"

    /// Full initialization sequence
    static let initSequence = [
        reset,
        echoOff,
        linefeedsOff,
        spacesOff,
        headersOff,
        autoProtocol,
        adaptiveTiming
    ]
}
