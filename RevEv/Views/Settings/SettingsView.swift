import SwiftUI

/// Settings view for app configuration
struct SettingsView: View {
    @EnvironmentObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.cyberpunkBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Audio Settings
                        settingsSection(title: "AUDIO") {
                            // Volume slider
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Master Volume")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(Int(viewModel.masterVolume * 100))%")
                                        .foregroundColor(.neonCyan)
                                        .font(.system(.body, design: .monospaced))
                                }

                                Slider(
                                    value: Binding(
                                        get: { viewModel.masterVolume },
                                        set: { viewModel.updateVolume($0) }
                                    ),
                                    in: 0...1
                                )
                                .tint(.neonCyan)
                            }

                            Divider().background(Color.cyberpunkBorder)

                            // Engine sound selection
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Engine Sound")
                                    .foregroundColor(.white)

                                ForEach(EngineConfiguration.all, id: \.id) { config in
                                    engineRow(config)
                                }
                            }
                        }

                        // Bluetooth Settings
                        settingsSection(title: "BLUETOOTH") {
                            // Auto-connect toggle
                            Toggle(isOn: $viewModel.bluetooth.isAutoConnectEnabled) {
                                VStack(alignment: .leading) {
                                    Text("Auto-Connect")
                                        .foregroundColor(.white)
                                    Text("Automatically connect to last device")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .tint(.neonCyan)

                            Divider().background(Color.cyberpunkBorder)

                            // Connection status
                            HStack {
                                Text("Status")
                                    .foregroundColor(.white)
                                Spacer()
                                Text(viewModel.connectionState.displayText)
                                    .foregroundColor(statusColor)
                                    .font(.system(.body, design: .monospaced))
                            }

                            if let deviceName = viewModel.connectedDeviceName {
                                HStack {
                                    Text("Device")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(deviceName)
                                        .foregroundColor(.gray)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }

                            Divider().background(Color.cyberpunkBorder)

                            // Connect/Disconnect button
                            Button(action: {
                                if viewModel.connectionState.isConnected {
                                    viewModel.disconnectBluetooth()
                                } else {
                                    viewModel.connectBluetooth()
                                }
                            }) {
                                HStack {
                                    Image(systemName: viewModel.connectionState.isConnected
                                          ? "antenna.radiowaves.left.and.right.slash"
                                          : "antenna.radiowaves.left.and.right")
                                    Text(viewModel.connectionState.isConnected ? "Disconnect" : "Scan for Devices")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.cyberpunkCard)
                                .foregroundColor(.neonCyan)
                                .cornerRadius(8)
                            }

                            // Discovered devices list
                            if !viewModel.bluetooth.discoveredDevices.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Discovered Devices")
                                        .foregroundColor(.gray)
                                        .font(.caption)

                                    ForEach(viewModel.bluetooth.discoveredDevices, id: \.identifier) { device in
                                        Button(action: {
                                            viewModel.bluetooth.connect(to: device)
                                        }) {
                                            HStack {
                                                Image(systemName: "car.fill")
                                                    .foregroundColor(.neonCyan)
                                                Text(device.name ?? "Unknown")
                                                    .foregroundColor(.white)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .foregroundColor(.gray)
                                            }
                                            .padding()
                                            .background(Color.cyberpunkCard)
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                            }
                        }

                        // About section
                        settingsSection(title: "ABOUT") {
                            HStack {
                                Text("Version")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("1.0.0")
                                    .foregroundColor(.gray)
                            }

                            HStack {
                                Text("Engine Audio")
                                    .foregroundColor(.white)
                                Spacer()
                                Text("Sample-based")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.neonCyan)
                }
            }
            .toolbarBackground(Color.cyberpunkBg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: - Helper Views

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.neonMagenta)

            VStack(spacing: 16) {
                content()
            }
            .padding()
            .background(Color.cyberpunkCard)
            .cornerRadius(12)
            .neonBorder(color: .neonMagenta.opacity(0.2), lineWidth: 1, glowRadius: 2)
        }
    }

    private func engineRow(_ config: EngineConfiguration) -> some View {
        Button(action: {
            viewModel.selectConfiguration(config)
        }) {
            HStack {
                Image(systemName: "engine.combustion")
                    .foregroundColor(isSelected(config) ? .neonCyan : .gray)

                VStack(alignment: .leading) {
                    Text(config.displayName)
                        .foregroundColor(.white)
                    Text("Redline: \(Int(config.limiter)) RPM")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                if isSelected(config) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.neonCyan)
                }
            }
            .padding()
            .background(isSelected(config) ? Color.neonCyan.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
    }

    private func isSelected(_ config: EngineConfiguration) -> Bool {
        config.id == viewModel.selectedConfiguration.id
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .connected: return .neonGreen
        case .scanning, .connecting, .initializing: return .neonYellow
        case .error: return .neonRed
        default: return .gray
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DashboardViewModel())
}
