import SwiftUI

/// Animated RPM gauge with cyberpunk styling
struct RPMGaugeView: View {
    let rpm: Double
    let maxRPM: Double
    let redlineRPM: Double

    @State private var animatedRPM: Double = 0

    private let startAngle: Double = 135
    private let endAngle: Double = 405
    private let tickCount = 10

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = size / 2 - 20

            ZStack {
                // Background arc
                arcPath(radius: radius, startAngle: startAngle, endAngle: endAngle)
                    .stroke(Color.cyberpunkBorder, lineWidth: 20)

                // Redline zone
                let redlineStartAngle = angleForRPM(redlineRPM)
                arcPath(radius: radius, startAngle: redlineStartAngle, endAngle: endAngle)
                    .stroke(Color.neonRed.opacity(0.5), lineWidth: 20)
                    .blur(radius: 3)

                arcPath(radius: radius, startAngle: redlineStartAngle, endAngle: endAngle)
                    .stroke(Color.neonRed, lineWidth: 20)

                // Active arc (current RPM)
                let currentAngle = angleForRPM(animatedRPM)
                arcPath(radius: radius, startAngle: startAngle, endAngle: currentAngle)
                    .stroke(
                        LinearGradient(
                            colors: [.neonCyan, animatedRPM > redlineRPM ? .neonRed : .neonMagenta],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 20
                    )
                    .blur(radius: 2)

                arcPath(radius: radius, startAngle: startAngle, endAngle: currentAngle)
                    .stroke(
                        LinearGradient(
                            colors: [.neonCyan, animatedRPM > redlineRPM ? .neonRed : .neonMagenta],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 16
                    )

                // Tick marks
                ForEach(0...tickCount, id: \.self) { i in
                    let tickRPM = Double(i) * maxRPM / Double(tickCount)
                    let angle = angleForRPM(tickRPM)
                    let isRedline = tickRPM >= redlineRPM

                    // Tick line
                    tickMark(at: angle, radius: radius - 25, length: 15, center: center)
                        .stroke(isRedline ? Color.neonRed : Color.white.opacity(0.8), lineWidth: 2)

                    // Tick label
                    let labelRadius = radius - 50
                    let labelAngle = Angle(degrees: angle - 90)
                    let x = center.x + labelRadius * cos(labelAngle.radians)
                    let y = center.y + labelRadius * sin(labelAngle.radians)

                    Text("\(Int(tickRPM / 1000))")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(isRedline ? .neonRed : .white.opacity(0.8))
                        .position(x: x, y: y)
                }

                // Center display
                VStack(spacing: 4) {
                    Text(formatRPM(animatedRPM))
                        .font(.system(size: 48, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: animatedRPM > redlineRPM ? .neonRed : .neonCyan, radius: 10)

                    Text("RPM")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .position(center)

                // Needle
                needleShape(angle: currentAngle, radius: radius - 35, center: center)
                    .fill(Color.white)
                    .shadow(color: .neonCyan, radius: 5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: rpm) { newValue in
            withAnimation(.interpolatingSpring(stiffness: 100, damping: 15)) {
                animatedRPM = newValue
            }
        }
        .onAppear {
            animatedRPM = rpm
        }
    }

    // MARK: - Helper Functions

    private func angleForRPM(_ rpm: Double) -> Double {
        let normalizedRPM = clamp(rpm, 0, maxRPM)
        let ratio = normalizedRPM / maxRPM
        return startAngle + ratio * (endAngle - startAngle)
    }

    private func arcPath(radius: CGFloat, startAngle: Double, endAngle: Double) -> Path {
        Path { path in
            path.addArc(
                center: .zero,
                radius: radius,
                startAngle: Angle(degrees: startAngle - 90),
                endAngle: Angle(degrees: endAngle - 90),
                clockwise: false
            )
        }
        .offsetBy(dx: radius + 20, dy: radius + 20)
    }

    private func tickMark(at angle: Double, radius: CGFloat, length: CGFloat, center: CGPoint) -> Path {
        let radians = CGFloat(Angle(degrees: angle - 90).radians)
        let innerRadius = radius
        let outerRadius = radius + length

        return Path { path in
            path.move(to: CGPoint(
                x: center.x + innerRadius * cos(radians),
                y: center.y + innerRadius * sin(radians)
            ))
            path.addLine(to: CGPoint(
                x: center.x + outerRadius * cos(radians),
                y: center.y + outerRadius * sin(radians)
            ))
        }
    }

    private func needleShape(angle: Double, radius: CGFloat, center: CGPoint) -> Path {
        let radians = CGFloat(Angle(degrees: angle - 90).radians)
        let needleLength = radius
        let needleWidth: CGFloat = 4

        let tip = CGPoint(
            x: center.x + needleLength * cos(radians),
            y: center.y + needleLength * sin(radians)
        )

        let baseLeft = CGPoint(
            x: center.x + needleWidth * cos(radians + .pi / 2),
            y: center.y + needleWidth * sin(radians + .pi / 2)
        )

        let baseRight = CGPoint(
            x: center.x + needleWidth * cos(radians - .pi / 2),
            y: center.y + needleWidth * sin(radians - .pi / 2)
        )

        return Path { path in
            path.move(to: tip)
            path.addLine(to: baseLeft)
            path.addLine(to: baseRight)
            path.closeSubpath()
        }
    }

    private func formatRPM(_ rpm: Double) -> String {
        return String(format: "%.0f", rpm)
    }
}

#Preview {
    ZStack {
        Color.cyberpunkBg.ignoresSafeArea()

        RPMGaugeView(rpm: 5500, maxRPM: 9000, redlineRPM: 8000)
            .frame(width: 350, height: 350)
    }
}
