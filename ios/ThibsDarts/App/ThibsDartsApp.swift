import SwiftUI

@main
struct ThibsDartsApp: App {
    var body: some Scene {
        WindowGroup {
            // Pour l'instant l'app ouvre l'installation du premier allumage.
            SetupFlow()
                .preferredColorScheme(.dark)
                .tint(Td.sunset)
        }
    }
}
