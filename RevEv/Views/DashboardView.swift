import SwiftUI

/// Main dashboard view with cyberpunk styling
struct DashboardView: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Background
            Color.cyberpunkBg
                .ignoresSafeArea()

            // Scanline overlay
            ScanlineOverlay()
                .opacity(0.03)
                .ignoresSafeArea()

            // Main content
            VStack(spacing: 0) {
                // Header
                headerView

                Spacer()

                // RPM Gauge
                RPMGaugeView(
                    rpm: viewModel.currentDisplayRPM,
                    maxRPM: viewModel.maxRPM,
                    redlineRPM: viewModel.redlineRPM
                )
                .frame(maxWidth: 350, maxHeight: 350)
                .padding(.horizontal)

                Spacer()

                // Info cards
                infoCardsView
                    .padding(.horizontal)

                Spacer()

                // Throttle bar
                LabeledThrottleBar(throttle: viewModel.throttle)
                    .padding(.horizontal, 24)

                Spacer()

                // Demo slider (when in demo mode)
                if viewModel.isDemoMode {
                    demoSliderView
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

                // Engine selector and controls
                controlsView
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            // Logo
            NeonText(
                text: "REVEV",
                color: .neonCyan,
                font: .system(size: 28, weight: .black, design: .monospaced),
                glowRadius: 8
            )

            Spacer()

            // Demo/Live indicator
            if viewModel.isDemoMode {
                Text("DEMO")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.neonYellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.neonYellow.opacity(0.2))
                    .cornerRadius(4)
            }

            // Connection status
            ConnectionStatusView(
                state: viewModel.connectionState,
                deviceName: viewModel.connectedDeviceName
            )
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Info Cards

    private var infoCardsView: some View {
        HStack(spacing: 16) {
            GearIndicatorView(gear: viewModel.gear, label: "GEAR")
            ThrottleIndicatorView(throttle: viewModel.throttle)
            SoundStatusView(isPlaying: viewModel.isPlaying)
        }
    }

    // MARK: - Demo Slider

    private var demoSliderView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("DEMO RPM")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)

                Spacer()

                Text("\(Int(viewModel.demoRPM))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.neonCyan)
            }

            Slider(
                value: Binding(
                    get: { viewModel.demoRPM },
                    set: { viewModel.updateDemoRPM($0) }
                ),
                in: 800...viewModel.maxRPM,
                step: 100
            )
            .tint(.neonCyan)
        }
        .padding()
        .background(Color.cyberpunkCard)
        .cornerRadius(12)
        .neonBorder(color: .neonCyan.opacity(0.3), lineWidth: 1, glowRadius: 2)
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: 12) {
            // Engine selector
            Menu {
                ForEach(EngineConfiguration.all, id: \.id) { config in
                    Button(action: {
                        viewModel.selectConfiguration(config)
                    }) {
                        HStack {
                            Text(config.displayName)
                            if config.id == viewModel.selectedConfiguration.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "engine.combustion")
                        .foregroundColor(.neonMagenta)

                    Text(viewModel.selectedConfiguration.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.cyberpunkCard)
                .cornerRadius(12)
                .neonBorder(color: .neonMagenta.opacity(0.3), lineWidth: 1, glowRadius: 2)
            }

            // Action buttons
            HStack(spacing: 12) {
                // Play/Stop button
                Button(action: { viewModel.togglePlayback() }) {
                    HStack {
                        Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                        Text(viewModel.isPlaying ? "STOP" : "START")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isPlaying ? Color.neonRed.opacity(0.3) : Color.neonGreen.opacity(0.3))
                    .foregroundColor(viewModel.isPlaying ? .neonRed : .neonGreen)
                    .cornerRadius(12)
                    .neonBorder(
                        color: (viewModel.isPlaying ? Color.neonRed : .neonGreen).opacity(0.5),
                        lineWidth: 1,
                        glowRadius: 3
                    )
                }

                // Demo/Live toggle
                Button(action: { viewModel.toggleDemoMode() }) {
                    HStack {
                        Image(systemName: viewModel.isDemoMode ? "antenna.radiowaves.left.and.right" : "slider.horizontal.3")
                        Text(viewModel.isDemoMode ? "LIVE" : "DEMO")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyberpunkCard)
                    .foregroundColor(.neonCyan)
                    .cornerRadius(12)
                    .neonBorder(color: .neonCyan.opacity(0.3), lineWidth: 1, glowRadius: 2)
                }

                // Settings button
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .frame(width: 50)
                        .padding()
                        .background(Color.cyberpunkCard)
                        .foregroundColor(.gray)
                        .cornerRadius(12)
                        .neonBorder(color: .gray.opacity(0.3), lineWidth: 1, glowRadius: 2)
                }
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(DashboardViewModel())
}
