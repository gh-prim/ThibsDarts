import Darwin
import SwiftUI

/// Cible ThibsDarts trouvée sur le Wi-Fi.
struct FoundPi: Identifiable, Hashable {
    let base: URL
    let owner: String
    var id: String { base.absoluteString }
}

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

/// Cherche les cibles : d'abord cet appareil (simulateur), puis tout le réseau local en /24.
enum Discovery {
    static func scan() async -> [FoundPi] {
        // Simulateur : le hub tourne sur le Mac, inutile de balayer le réseau.
        if let me = await probe(URL(string: "http://127.0.0.1:8420")!) { return [me] }
        var hosts: [String] = []
        if let ip = localIPv4() {
            let parts = ip.split(separator: ".")
            if parts.count == 4 {
                let prefix = parts.prefix(3).joined(separator: ".")
                hosts += (1...254).map { "\(prefix).\($0)" }.filter { $0 != ip }
            }
        }
        let urls = hosts.compactMap { URL(string: "http://\($0):8420") }
        return await withTaskGroup(of: FoundPi?.self) { group in
            var out: [FoundPi] = []
            var next = 0
            while next < min(48, urls.count) {
                let url = urls[next]
                next += 1
                group.addTask { await probe(url) }
            }
            while let r = await group.next() {
                if let r, !out.contains(where: { $0.owner == r.owner }) { out.append(r) }
                if next < urls.count {
                    let url = urls[next]
                    next += 1
                    group.addTask { await probe(url) }
                }
            }
            return out
        }
    }

    private static func probe(_ url: URL) async -> FoundPi? {
        guard let h = await LobbyAPI.hello(at: url, timeout: 1.5) else { return nil }
        return FoundPi(base: url, owner: h.owner ?? "Thibs")
    }

    /// Adresse IPv4 Wi-Fi ou Ethernet de l'Apple TV.
    static func localIPv4() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var best: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: a.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if name == "en0" { return ip }
                best = best ?? ip
            }
        }
        return best
    }
}
