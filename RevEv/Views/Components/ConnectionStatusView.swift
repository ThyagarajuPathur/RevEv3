import SwiftUI

/// Connection status indicator with pulsing animation
struct ConnectionStatusView: View {
    let state: ConnectionState
    let deviceName: String?

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .shadow(color: statusColor, radius: isPulsing ? 8 : 4)
                .scaleEffect(isPulsing ? 1.2 : 1.0)

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)

                if let name = deviceName, state.isConnected {
                    Text(name)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.cyberpunkCard)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(statusColor.opacity(0.5), lineWidth: 1)
        )
        .onAppear {
            startPulsingIfNeeded()
        }
        .onChange(of: state) { _ in
            startPulsingIfNeeded()
        }
    }

    private var statusColor: Color {
        switch state {
        case .connected:
            return .neonGreen
        case .scanning, .connecting, .initializing:
            return .neonYellow
        case .disconnected:
            return .gray
        case .error:
            return .neonRed
        }
    }

    private var statusText: String {
        switch state {
        case .connected:
            return "CONNECTED"
        case .scanning:
            return "SCANNING..."
        case .connecting:
            return "CONNECTING..."
        case .initializing:
            return "INITIALIZING..."
        case .disconnected:
            return "DISCONNECTED"
        case .error(let msg):
            return "ERROR: \(msg.uppercased())"
        }
    }

    private func startPulsingIfNeeded() {
        let shouldPulse = state == .scanning || state == .connecting || state == .initializing

        if shouldPulse {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                isPulsing = false
            }
        }
    }
}

#Preview {
    ZStack {
        Color.cyberpunkBg.ignoresSafeArea()

        VStack(spacing: 20) {
            ConnectionStatusView(state: .connected, deviceName: "Veepeak OBD")
            ConnectionStatusView(state: .scanning, deviceName: nil)
            ConnectionStatusView(state: .connecting, deviceName: nil)
            ConnectionStatusView(state: .disconnected, deviceName: nil)
            ConnectionStatusView(state: .error("Timeout"), deviceName: nil)
        }
    }
}
