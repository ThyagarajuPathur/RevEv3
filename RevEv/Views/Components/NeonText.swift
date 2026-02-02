import SwiftUI

/// Cyberpunk-style text with neon glow effect
struct NeonText: View {
    let text: String
    var color: Color = .cyan
    var font: Font = .system(size: 24, weight: .bold, design: .monospaced)
    var glowRadius: CGFloat = 10

    var body: some View {
        ZStack {
            // Glow layer (multiple for stronger effect)
            Text(text)
                .font(font)
                .foregroundColor(color)
                .blur(radius: glowRadius)

            Text(text)
                .font(font)
                .foregroundColor(color)
                .blur(radius: glowRadius / 2)

            // Main text
            Text(text)
                .font(font)
                .foregroundColor(.white)
        }
    }
}

/// Cyberpunk color palette
extension Color {
    static let neonCyan = Color(red: 0, green: 1, blue: 1)
    static let neonMagenta = Color(red: 1, green: 0, blue: 1)
    static let neonYellow = Color(red: 1, green: 1, blue: 0)
    static let neonRed = Color(red: 1, green: 0.2, blue: 0.2)
    static let neonGreen = Color(red: 0.2, green: 1, blue: 0.4)

    static let cyberpunkBg = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let cyberpunkCard = Color(red: 0.08, green: 0.08, blue: 0.12)
    static let cyberpunkBorder = Color(red: 0.2, green: 0.2, blue: 0.3)
}

/// Neon border modifier
struct NeonBorder: ViewModifier {
    var color: Color = .neonCyan
    var lineWidth: CGFloat = 2
    var glowRadius: CGFloat = 5

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color, lineWidth: lineWidth)
                    .blur(radius: glowRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color, lineWidth: lineWidth)
            )
    }
}

extension View {
    func neonBorder(color: Color = .neonCyan, lineWidth: CGFloat = 2, glowRadius: CGFloat = 5) -> some View {
        modifier(NeonBorder(color: color, lineWidth: lineWidth, glowRadius: glowRadius))
    }
}

/// Scanline overlay effect
struct ScanlineOverlay: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 2) {
                ForEach(0..<Int(geometry.size.height / 4), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.1))
                        .frame(height: 1)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 3)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color.cyberpunkBg.ignoresSafeArea()

        VStack(spacing: 30) {
            NeonText(text: "REVEV", color: .neonCyan, font: .system(size: 48, weight: .black, design: .monospaced))

            NeonText(text: "7,200 RPM", color: .neonMagenta)

            Text("Normal Text")
                .foregroundColor(.white)
                .padding()
                .background(Color.cyberpunkCard)
                .neonBorder()
        }
    }
}
