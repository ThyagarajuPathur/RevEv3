import AVFoundation
import Combine

/// Represents a playable audio sample with gain and pitch control
class AudioSample {
    let playerNode: AVAudioPlayerNode
    let pitchNode: AVAudioUnitTimePitch
    let mixerNode: AVAudioMixerNode
    let buffer: AVAudioPCMBuffer
    let referenceRPM: Double
    let baseVolume: Double

    var isPlaying: Bool = false

    init(playerNode: AVAudioPlayerNode,
         pitchNode: AVAudioUnitTimePitch,
         mixerNode: AVAudioMixerNode,
         buffer: AVAudioPCMBuffer,
         referenceRPM: Double,
         baseVolume: Double) {
        self.playerNode = playerNode
        self.pitchNode = pitchNode
        self.mixerNode = mixerNode
        self.buffer = buffer
        self.referenceRPM = referenceRPM
        self.baseVolume = baseVolume
    }

    /// Set the gain (0-1) for this sample
    func setGain(_ gain: Double) {
        mixerNode.outputVolume = Float(gain * baseVolume)
    }

    /// Set pitch in cents relative to reference RPM
    func setPitch(cents: Double) {
        pitchNode.pitch = Float(cents)
    }

    /// Start looped playback
    func play() {
        guard !isPlaying else { return }
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        playerNode.play()
        isPlaying = true
    }

    /// Stop playback
    func stop() {
        playerNode.stop()
        isPlaying = false
    }
}

/// Main audio engine that manages engine sound playback
class AudioEngine: ObservableObject {
    private var engine: AVAudioEngine?
    private var samples: [SoundKey: AudioSample] = [:]
    private var currentConfiguration: EngineConfiguration?

    @Published var isRunning: Bool = false
    @Published var masterVolume: Float = 0.8

    // Crossfade thresholds
    private let lowHighCrossfadeStart: Double = 3000
    private let lowHighCrossfadeEnd: Double = 6500

    init() {
        setupEngine()
    }

    // MARK: - Setup

    private func setupEngine() {
        engine = AVAudioEngine()
    }

    /// Load an engine configuration and prepare all samples
    func loadConfiguration(_ config: EngineConfiguration) async throws {
        // Stop current playback
        stop()

        // Clear existing samples
        samples.removeAll()

        guard let engine = engine else {
            throw AudioEngineError.engineNotInitialized
        }

        // Load each sound
        for (key, source) in config.sounds {
            do {
                let sample = try loadSample(source: source, in: engine, folder: config.name)
                samples[key] = sample
            } catch {
                print("Warning: Failed to load sample \(key.rawValue): \(error)")
            }
        }

        currentConfiguration = config

        // Connect and start engine
        try engine.start()
        isRunning = true

        // Start all samples (they'll be silent initially)
        for sample in samples.values {
            sample.setGain(0)
            sample.play()
        }
    }

    private func loadSample(source: SoundSource, in engine: AVAudioEngine, folder: String) throws -> AudioSample {
        // Try to find the audio file
        guard let url = findAudioFile(named: source.filename, in: folder) else {
            throw AudioEngineError.fileNotFound(source.filename)
        }

        // Load audio file
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat

        // Create buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioEngineError.bufferCreationFailed
        }
        try file.read(into: buffer)

        // Create nodes
        let playerNode = AVAudioPlayerNode()
        let pitchNode = AVAudioUnitTimePitch()
        let mixerNode = AVAudioMixerNode()

        // Add nodes to engine
        engine.attach(playerNode)
        engine.attach(pitchNode)
        engine.attach(mixerNode)

        // Connect: player -> pitch -> mixer -> main mixer
        engine.connect(playerNode, to: pitchNode, format: format)
        engine.connect(pitchNode, to: mixerNode, format: format)
        engine.connect(mixerNode, to: engine.mainMixerNode, format: format)

        // Set initial volume to 0
        mixerNode.outputVolume = 0

        return AudioSample(
            playerNode: playerNode,
            pitchNode: pitchNode,
            mixerNode: mixerNode,
            buffer: buffer,
            referenceRPM: source.referenceRPM,
            baseVolume: source.volume
        )
    }

    private func findAudioFile(named name: String, in folder: String) -> URL? {
        let extensions = ["wav", "mp3", "m4a", "aiff"]

        for ext in extensions {
            // Try in folder
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds/\(folder)") {
                return url
            }
            // Try in root Sounds folder
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Sounds") {
                return url
            }
            // Try without subdirectory
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }

        return nil
    }

    // MARK: - Playback Control

    func start() {
        guard let engine = engine, !engine.isRunning else { return }
        do {
            try engine.start()
            isRunning = true
            for sample in samples.values {
                sample.play()
            }
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func stop() {
        for sample in samples.values {
            sample.stop()
        }
        engine?.stop()
        isRunning = false
    }

    // MARK: - Sound Application (ported from Engine.ts)

    /// Apply sound modulation based on current RPM and throttle
    /// This is the core audio logic ported from the TypeScript version
    func applySounds(rpm: Double, throttle: Double) {
        guard let config = currentConfiguration else { return }

        // Calculate crossfades
        let (highGain, lowGain) = crossFade(rpm, start: lowHighCrossfadeStart, end: lowHighCrossfadeEnd)
        let (onGain, offGain) = crossFade(throttle, start: 0, end: 1)

        // Calculate limiter gain
        let limiterGain = ratio(rpm, config.softLimiter * 0.93, config.limiter)

        // Apply to each sample
        applySample(.onLow, gain: onGain * lowGain, rpm: rpm)
        applySample(.offLow, gain: offGain * lowGain, rpm: rpm)
        applySample(.onHigh, gain: onGain * highGain, rpm: rpm)
        applySample(.offHigh, gain: offGain * highGain, rpm: rpm)
        applySample(.limiter, gain: limiterGain, rpm: rpm, applyPitch: false)

        // Apply master volume
        engine?.mainMixerNode.outputVolume = masterVolume
    }

    private func applySample(_ key: SoundKey, gain: Double, rpm: Double, applyPitch: Bool = true) {
        guard let sample = samples[key], let config = currentConfiguration else { return }

        // Set gain
        sample.setGain(gain)

        // Apply pitch shift based on RPM difference from reference
        if applyPitch {
            let pitchCents = (rpm - sample.referenceRPM) * config.rpmPitchFactor
            sample.setPitch(cents: pitchCents)
        }
    }

    // MARK: - Cleanup

    deinit {
        stop()
        engine = nil
    }
}

// MARK: - Errors

enum AudioEngineError: Error, LocalizedError {
    case engineNotInitialized
    case fileNotFound(String)
    case bufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .engineNotInitialized:
            return "Audio engine not initialized"
        case .fileNotFound(let name):
            return "Audio file not found: \(name)"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        }
    }
}
