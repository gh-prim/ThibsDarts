import SwiftUI

/// L'Apple TV suit le salon et la partie d'une cible (planches Apple TV).
@MainActor
final class TVModel: ObservableObject {
    enum Phase: Equatable { case searching, choose, connected, lost }

    @Published var phase: Phase = .searching
    @Published var found: [FoundPi] = []
    @Published private(set) var base: URL?
    @Published private(set) var info: LobbyInfo?

    /// Interstitiel "À Max." quand le joueur change.
    @Published var nextUp: NextUp?
    /// Fête 180 en cours.
    @Published var fete180 = false
    /// Mini player Spotify (compte du propriétaire relié sur le Pi).
    @Published var music: NowPlaying?

    struct NextUp: Equatable {
        let name: String
        let previous: String?
        let previousScore: Int?
        let previousRemaining: Int?
    }

    private let defaults = UserDefaults.standard
    private var lastCurrent: String?
    private var lastTurnScore = 0
    private var last180Key: String?
    private var misses = 0

    init() {
        base = defaults.url(forKey: "tvPiBase")
    }

    // MARK: Connexion

    func start() async {
        if let base, await LobbyAPI.hello(at: base) != nil {
            phase = .connected
            return
        }
        await search()
    }

    func search() async {
        phase = .searching
        found = await Discovery.scan()
        if found.count == 1 {
            choose(found[0])
        } else {
            phase = found.isEmpty ? .lost : .choose
        }
    }

    func choose(_ pi: FoundPi) {
        base = pi.base
        misses = 0
        defaults.set(pi.base, forKey: "tvPiBase")
        phase = .connected
    }

    /// Suit le salon en boucle : 1 s en partie, 2 s sinon. Lancé par l'écran connecté.
    func follow() async {
        while !Task.isCancelled, phase == .connected, let base {
            do {
                let i = try await LobbyAPI.lobby(at: base)
                misses = 0
                react(to: i)
                info = i
            } catch {
                misses += 1
                if misses >= 10 { phase = .lost }
            }
            try? await Task.sleep(for: .seconds(info?.isPlaying == true ? 1 : 2))
        }
    }

    // MARK: Spotify

    /// Suit la musique toutes les 3 s. Lancé par l'écran connecté.
    func followMusic() async {
        while !Task.isCancelled, phase == .connected, let base {
            let now = await LobbyAPI.nowPlaying(at: base)
            withAnimation(Td.sortie) { music = now?.active == true ? now : nil }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    /// Télécommande : lecture/pause, piste suivante ou précédente.
    func music(_ action: String) {
        guard let base, let m = music else { return }
        let a = action == "toggle" ? (m.playing == true ? "pause" : "play") : action
        if a == "pause" || a == "play" { music?.playing = a == "play" }
        Task {
            await LobbyAPI.spotify(a, at: base)
            try? await Task.sleep(for: .milliseconds(400))
            if let now = await LobbyAPI.nowPlaying(at: base) { music = now.active == true ? now : nil }
        }
    }

    // MARK: Moments forts

    private func react(to new: LobbyInfo) {
        guard let g = new.game, new.isPlaying else {
            lastCurrent = nil
            return
        }
        // 180 en X01
        if g.isX01, g.darts.count == 3, g.darts.allSatisfy({ $0.label == "T20" }) {
            let key = "\(g.leg)-\(g.current)-\(g.players.map(\.remaining))"
            if key != last180Key {
                last180Key = key
                withAnimation(Td.sortie) { fete180 = true }
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    withAnimation(Td.sortie) { self.fete180 = false }
                }
            }
        }
        // Joueur suivant
        if g.winner == nil, let prev = lastCurrent, prev != g.current, g.darts.isEmpty {
            let p = g.players.first { $0.name == prev }
            let up = NextUp(name: g.current, previous: prev, previousScore: lastTurnScore, previousRemaining: p?.remaining)
            withAnimation(Td.sortie) { nextUp = up }
            Task {
                try? await Task.sleep(for: .seconds(3.5))
                if self.nextUp == up { withAnimation(Td.sortie) { self.nextUp = nil } }
            }
        }
        lastCurrent = g.current
        lastTurnScore = g.turnScore
    }

    func photoURL(_ name: String) -> URL? {
        guard let base, let p = info?.players.first(where: { $0.name == name }) else { return nil }
        return LobbyAPI.photoURL(base: base, player: p)
    }
}

