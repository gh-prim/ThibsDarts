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
    @Published var volee0 = false
    @Published var plein20 = false
    @Published var bust = false
    /// Tournoi de la cible (null sans tournoi).
    @Published private(set) var tournament: TournamentInfo?
    /// Le prochain match a changé à cette date : l'annonce passe d'abord, puis le tableau.
    @Published private(set) var focusSince = Date()
    /// Tournoi fini vu en direct : le tableau final reste affiché un moment.
    private var finishedAt: Date?

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

    private var last0Key: String?
    private var last20Key: String?
    private var lastBustKey: String?
    private var misses = 0

    init() {
        base = defaults.url(forKey: "tvPiBase")
        // Dev : forcer une cible (simulateur pointé sur un hub de test).
        if let s = ProcessInfo.processInfo.environment["THIBSDARTS_PI"], let u = URL(string: s) { base = u }
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
                if let t = try? await LobbyAPI.tournament(at: base) {
                    follow(t)
                } else {
                    tournament = nil
                }
            } catch {
                misses += 1
                if misses >= 10 { phase = .lost }
            }
            try? await Task.sleep(for: .seconds(info?.isPlaying == true ? 1 : 2))
        }
    }

    private func follow(_ t: TournamentInfo) {
        if t.next != tournament?.next { focusSince = Date() }
        if t.state == "fini", tournament != nil, tournament?.state != "fini" { finishedAt = Date() }
        tournament = t
    }

    /// Tournoi à montrer quand aucune partie ne tourne : tirage fait, en cours, ou fini depuis moins de 15 min.
    var shownTournament: TournamentInfo? {
        guard let t = tournament else { return nil }
        switch t.state {
        case "tirage", "en_cours": return t
        case "fini": return finishedAt.map { Date().timeIntervalSince($0) < 900 } == true ? t : nil
        default: return nil
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
                // La vidéo remet fete180 à false à la fin ; filet de sécurité si elle ne finit pas.
                withAnimation(Td.sortie) { fete180 = true }
                Task {
                    try? await Task.sleep(for: .seconds(9))
                    if self.last180Key == key { withAnimation(Td.sortie) { self.fete180 = false } }
                }
            }
        }
        // Bust en X01
        if g.isX01, g.bust {
            let key = "\(g.leg)-\(g.current)-\(g.darts.map(\.label))-\(g.players.map(\.remaining))"
            if key != lastBustKey {
                lastBustKey = key
                withAnimation(Td.sortie) { bust = true }
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    if self.lastBustKey == key { withAnimation(Td.sortie) { self.bust = false } }
                }
            }
        }
        // 3 fléchettes dans le 20 en X01 (hors 180)
        if g.isX01, g.darts.count == 3, g.darts.allSatisfy({ ["S20", "D20", "T20"].contains($0.label) }),
           !g.darts.allSatisfy({ $0.label == "T20" }) {
            let key = "\(g.leg)-\(g.current)-\(g.players.map(\.remaining))-20"
            if key != last20Key {
                last20Key = key
                withAnimation(Td.sortie) { plein20 = true }
                Task {
                    try? await Task.sleep(for: .seconds(9))
                    if self.last20Key == key { withAnimation(Td.sortie) { self.plein20 = false } }
                }
            }
        }
        // Volée à 0 en X01 (3 fléchettes hors cible)
        if g.isX01, g.darts.count == 3, g.darts.allSatisfy({ $0.label == "MISS" }) {
            let key = "\(g.leg)-\(g.current)-\(g.players.map(\.remaining))-0"
            if key != last0Key {
                last0Key = key
                withAnimation(Td.sortie) { volee0 = true }
                Task {
                    try? await Task.sleep(for: .seconds(11))
                    if self.last0Key == key { withAnimation(Td.sortie) { self.volee0 = false } }
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

