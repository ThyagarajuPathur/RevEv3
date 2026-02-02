import SwiftUI
import Combine

/// Main view model that coordinates Bluetooth, Audio, and UI state
@MainActor
class DashboardViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var rpm: Double = 0
    @Published var throttle: Double = 0
    @Published var gear: Int? = nil
    @Published var isPlaying: Bool = false
    @Published var isDemoMode: Bool = true
    @Published var demoRPM: Double = 1000

    @Published var selectedConfiguration: EngineConfiguration = .bacMono
    @Published var masterVolume: Double = 0.8
    @Published var isAutoConnectEnabled: Bool = true {
        didSet {
            bluetooth.isAutoConnectEnabled = isAutoConnectEnabled
        }
    }

    // MARK: - Services

    var bluetooth = BluetoothService()
    let audioEngine = AudioEngine()

    // MARK: - Private Properties

    private var rpmHistory = RPMHistory()
    private var displayLink: CADisplayLink?
    private var cancellables = Set<AnyCancellable>()
    private var lastRPM: Double = 0

    // MARK: - Initialization

    init() {
        setupBindings()
        setupDisplayLink()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Observe Bluetooth RPM changes
        bluetooth.$currentRPM
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rpm in
                guard let self = self, !self.isDemoMode else { return }
                self.updateRPM(Double(rpm))
            }
            .store(in: &cancellables)
    }

    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(updateAudio))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateAudio() {
        guard isPlaying else { return }

        let currentRPM = isDemoMode ? demoRPM : rpm
        audioEngine.applySounds(rpm: currentRPM, throttle: throttle)
    }

    // MARK: - Public Methods

    /// Start audio playback
    func start() {
        Task {
            do {
                try await audioEngine.loadConfiguration(selectedConfiguration)
                isPlaying = true
            } catch {
                print("Failed to start audio: \(error)")
            }
        }
    }

    /// Stop audio playback
    func stop() {
        audioEngine.stop()
        isPlaying = false
    }

    /// Toggle playback state
    func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }

    /// Switch engine configuration
    func selectConfiguration(_ config: EngineConfiguration) {
        selectedConfiguration = config

        if isPlaying {
            Task {
                try? await audioEngine.loadConfiguration(config)
            }
        }
    }

    /// Toggle demo mode
    func toggleDemoMode() {
        isDemoMode.toggle()

        if !isDemoMode {
            bluetooth.startAutoConnect()
        }
    }

    /// Update RPM value (from OBD or demo)
    func updateRPM(_ newRPM: Double) {
        let clampedRPM = clamp(newRPM, 0, selectedConfiguration.limiter)

        // Calculate throttle from RPM change
        let deltaRPM = clampedRPM - lastRPM
        let deltaTime: Double = 1.0 / 60.0 // Assume 60fps

        if deltaTime > 0 {
            let rpmRate = deltaRPM / deltaTime
            let maxRate: Double = 2000 // RPM/second for full throttle
            let newThrottle = clamp(rpmRate / maxRate, 0, 1)

            // Smooth throttle
            throttle = lerp(throttle, newThrottle, 0.3)
        }

        rpm = clampedRPM
        lastRPM = clampedRPM

        // Add to history
        rpmHistory.add(rpm: Int(clampedRPM))
    }

    /// Update demo RPM (from slider)
    func updateDemoRPM(_ newRPM: Double) {
        let previousRPM = demoRPM
        demoRPM = clamp(newRPM, 800, selectedConfiguration.limiter)

        // Calculate throttle from change
        let delta = demoRPM - previousRPM
        if abs(delta) > 10 {
            let newThrottle = clamp(delta / 500, 0, 1)
            throttle = lerp(throttle, newThrottle, 0.5)
        } else {
            throttle = lerp(throttle, 0, 0.1)
        }
    }

    /// Update volume
    func updateVolume(_ volume: Double) {
        masterVolume = volume
        audioEngine.masterVolume = Float(volume)
    }

    /// Connect to Bluetooth device
    func connectBluetooth() {
        bluetooth.startScanning()
    }

    /// Disconnect from Bluetooth device
    func disconnectBluetooth() {
        bluetooth.disconnect()
    }

    // MARK: - Computed Properties

    var connectionState: ConnectionState {
        bluetooth.connectionState
    }

    var connectedDeviceName: String? {
        bluetooth.connectedDeviceName
    }

    var maxRPM: Double {
        selectedConfiguration.limiter
    }

    var redlineRPM: Double {
        selectedConfiguration.softLimiter
    }

    var currentDisplayRPM: Double {
        isDemoMode ? demoRPM : rpm
    }

    // MARK: - Cleanup

    deinit {
        displayLink?.invalidate()
    }
}
