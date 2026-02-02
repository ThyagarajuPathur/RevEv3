import SwiftUI

/// Gear indicator display with cyberpunk styling
struct GearIndicatorView: View {
    let gear: Int?
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(gearText)
                .font(.system(size: 36, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .shadow(color: .neonCyan, radius: 5)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
        }
        .frame(width: 70, height: 70)
        .background(Color.cyberpunkCard)
        .neonBorder(color: .neonCyan.opacity(0.5), lineWidth: 1, glowRadius: 3)
        .cornerRadius(12)
    }

    private var gearText: String {
        if let gear = gear {
            return gear == 0 ? "N" : "\(gear)"
        }
        return "—"
    }
}

/// Throttle position indicator
struct ThrottleIndicatorView: View {
    let throttle: Double

    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(throttle * 100))%")
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .shadow(color: throttleColor, radius: 5)

            Text("THR")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
        }
        .frame(width: 70, height: 70)
        .background(Color.cyberpunkCard)
        .neonBorder(color: throttleColor.opacity(0.5), lineWidth: 1, glowRadius: 3)
        .cornerRadius(12)
    }

    private var throttleColor: Color {
        if throttle > 0.8 {
            return .neonMagenta
        } else if throttle > 0.5 {
            return .neonYellow
        }
        return .neonCyan
    }
}

/// Sound status indicator
struct SoundStatusView: View {
    let isPlaying: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(isPlaying ? "ON" : "OFF")
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .shadow(color: isPlaying ? .neonGreen : .gray, radius: 5)

            Text("SOUND")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
        }
        .frame(width: 70, height: 70)
        .background(Color.cyberpunkCard)
        .neonBorder(color: (isPlaying ? Color.neonGreen : .gray).opacity(0.5), lineWidth: 1, glowRadius: 3)
        .cornerRadius(12)
    }
}

#Preview {
    ZStack {
        Color.cyberpunkBg.ignoresSafeArea()

        HStack(spacing: 20) {
            GearIndicatorView(gear: 3, label: "GEAR")
            ThrottleIndicatorView(throttle: 0.65)
            SoundStatusView(isPlaying: true)
        }
    }
}
