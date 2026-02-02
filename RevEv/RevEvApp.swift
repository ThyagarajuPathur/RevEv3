import SwiftUI
import AVFoundation

@main
struct RevEvApp: App {
    @StateObject private var viewModel = DashboardViewModel()

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
}
