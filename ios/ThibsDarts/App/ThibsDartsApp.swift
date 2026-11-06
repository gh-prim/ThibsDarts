import SwiftUI

@main
struct ThibsDartsApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if app.onboarded && app.hasProfile {
                    HomeView()
                } else {
                    OnboardingFlow()
                }
            }
            .environmentObject(app)
            .preferredColorScheme(.dark)
            .tint(Td.sunset)
        }
    }
}
