import SwiftUI

/// Horizontal throttle bar with gradient fill
struct ThrottleBarView: View {
    let throttle: Double

    @State private var animatedThrottle: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.cyberpunkCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.cyberpunkBorder, lineWidth: 1)
                    )

                // Fill
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geometry.size.width * animatedThrottle - 4))
                    .padding(2)
                    .shadow(color: glowColor, radius: 5)

                // Tick marks
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 1)

                        if i < 9 {
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(height: 24)
        .onChange(of: throttle) { newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                animatedThrottle = newValue
            }
        }
        .onAppear {
            animatedThrottle = throttle
        }
    }

    private var gradientColors: [Color] {
        if animatedThrottle > 0.8 {
            return [.neonCyan, .neonMagenta, .neonRed]
        } else if animatedThrottle > 0.5 {
            return [.neonCyan, .neonMagenta]
        }
        return [.neonCyan, .neonCyan.opacity(0.7)]
    }

    private var glowColor: Color {
        if animatedThrottle > 0.8 {
            return .neonMagenta
        }
        return .neonCyan
    }
}

/// Labeled throttle bar
struct LabeledThrottleBar: View {
    let throttle: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("THROTTLE")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)

                Spacer()

                Text("\(Int(throttle * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }

            ThrottleBarView(throttle: throttle)
        }
    }
}

#Preview {
    ZStack {
        Color.cyberpunkBg.ignoresSafeArea()

        VStack(spacing: 30) {
            LabeledThrottleBar(throttle: 0.3)
            LabeledThrottleBar(throttle: 0.6)
            LabeledThrottleBar(throttle: 0.9)
        }
        .padding()
    }
}
