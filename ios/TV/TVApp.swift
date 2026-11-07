import SwiftUI

@main
struct ThibsDartsTVApp: App {
    @StateObject private var model = TVModel()

    var body: some Scene {
        WindowGroup {
            TVRoot()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .task { await model.start() }
        }
    }
}

/// Aiguille selon la connexion puis l'état du salon.
struct TVRoot: View {
    @EnvironmentObject var model: TVModel

    var body: some View {
        TVStage {
            switch model.phase {
            case .searching: TVSearchView()
            case .choose, .lost: TVConnexionView()
            case .connected: TVLiveView()
            }
        }
        .foregroundStyle(Td.ink)
        .animation(Td.sortie, value: model.phase)
    }
}
