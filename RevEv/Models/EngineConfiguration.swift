import Foundation

/// Represents an audio sample source with metadata
struct SoundSource: Codable {
    let filename: String
    let referenceRPM: Double
    let volume: Double

    init(filename: String, referenceRPM: Double, volume: Double = 1.0) {
        self.filename = filename
        self.referenceRPM = referenceRPM
        self.volume = volume
    }
}

/// Sound keys used in engine configurations
enum SoundKey: String, CaseIterable {
    case onLow = "on_low"
    case offLow = "off_low"
    case onHigh = "on_high"
    case offHigh = "off_high"
    case limiter = "limiter"
}

/// Complete engine sound configuration
struct EngineConfiguration: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
    let limiter: Double
    let softLimiter: Double
    let sounds: [SoundKey: SoundSource]

    /// RPM pitch factor for detuning samples
    var rpmPitchFactor: Double = 0.2
}

// MARK: - Predefined Configurations

extension EngineConfiguration {

    /// BAC Mono - High-revving lightweight sports car
    static let bacMono = EngineConfiguration(
        name: "bac_mono",
        displayName: "BAC Mono V8",
        limiter: 9000,
        softLimiter: 8950,
        sounds: [
            .onHigh: SoundSource(filename: "BAC_Mono_onhigh", referenceRPM: 1000, volume: 0.5),
            .onLow: SoundSource(filename: "BAC_Mono_onlow", referenceRPM: 1000, volume: 0.5),
            .offHigh: SoundSource(filename: "BAC_Mono_offveryhigh", referenceRPM: 1000, volume: 0.5),
            .offLow: SoundSource(filename: "BAC_Mono_offlow", referenceRPM: 1000, volume: 0.5),
            .limiter: SoundSource(filename: "limiter", referenceRPM: 8000, volume: 0.4)
        ]
    )

    /// Ferrari 458 - Exotic Italian V8
    static let ferrari458 = EngineConfiguration(
        name: "ferrari_458",
        displayName: "Ferrari 458 V8",
        limiter: 8900,
        softLimiter: 8800,
        sounds: [
            .onHigh: SoundSource(filename: "power_2", referenceRPM: 7700, volume: 2.5),
            .onLow: SoundSource(filename: "mid_res_2", referenceRPM: 5300, volume: 1.5),
            .offHigh: SoundSource(filename: "off_higher", referenceRPM: 7900, volume: 1.6),
            .offLow: SoundSource(filename: "off_midhigh", referenceRPM: 6900, volume: 1.4),
            .limiter: SoundSource(filename: "limiter_458", referenceRPM: 0, volume: 1.8)
        ]
    )

    /// ProCar - Vintage racing engine
    static let procar = EngineConfiguration(
        name: "procar",
        displayName: "ProCar Racing",
        limiter: 9000,
        softLimiter: 9000,
        sounds: [
            .onHigh: SoundSource(filename: "on_midhigh", referenceRPM: 8000, volume: 1.0),
            .onLow: SoundSource(filename: "on_low", referenceRPM: 3200, volume: 1.0),
            .offHigh: SoundSource(filename: "off_midhigh", referenceRPM: 8430, volume: 1.3),
            .offLow: SoundSource(filename: "off_lower", referenceRPM: 3400, volume: 1.3),
            .limiter: SoundSource(filename: "limiter", referenceRPM: 8000, volume: 0.5)
        ]
    )

    /// All available configurations
    static let all: [EngineConfiguration] = [.bacMono, .ferrari458, .procar]
}
