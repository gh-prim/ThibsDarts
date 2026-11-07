import Foundation

// Partagé entre l'app iPhone et l'app Apple TV.

enum PiError: LocalizedError {
    case unreachable, badCode, http(Int, String)

    var errorDescription: String? {
        switch self {
        case .unreachable: "Le Pi ne répond pas. Vérifie que ton iPhone est sur son Wi-Fi."
        case .badCode: "Mauvais code. Regarde celui affiché sur le Pi."
        case let .http(code, msg): "Le Pi a répondu \(code) (\(msg))."
        }
    }
}

// MARK: Salon

struct LobbyPlayer: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let host: Bool
    let guest: Bool
    let photo: Bool
    let connected: Bool
    /// false : l'hôte regarde sans jouer.
    var playing: Bool?
}

struct LiveDart: Decodable, Equatable {
    let label: String
    let value: Int
}

struct LivePlayer: Decodable, Equatable {
    let name: String
    let remaining: Int
    let average: Double?
    let legs: Int
    /// Ligne propre au mode ("au 7", "2 demis", vies).
    var detail: String?
    /// Cricket : marques sur 20, 19, 18, 17, 16, 15 et bull.
    var marks: [Int]?
}

struct LiveStat: Decodable, Equatable {
    let label: String
    let value: String
}

/// Partie en direct publiée par le Pi.
struct LiveGame: Decodable, Equatable {
    let mode: String
    let leg: Int
    let legsToWin: Int
    let current: String
    let next: String
    let turnScore: Int
    let darts: [LiveDart]
    let bust: Bool
    let checkout: [String]?
    let players: [LivePlayer]
    let winner: String?

    // Autres modes que le X01 (absents en 301 et 501).
    var title: String?
    var kind: String?
    var scoreLabel: String?
    var scoreValue: Int?
    var youLabel: String?

    // Fin de partie : stats du gagnant, tag et phrase propres au mode.
    var stats: [LiveStat]?
    var endTag: String?
    var endCopy: String?

    var isX01: Bool { kind == nil }
}

struct LobbyInfo: Decodable, Equatable {
    let state: String
    var game: LiveGame?
    let code: String?
    let hostName: String
    let label: String
    let players: [LobbyPlayer]
    var you: String?

    var isOpen: Bool { state == "open" }
    var isPlaying: Bool { state == "playing" }
}

/// Lien du QR code d'un salon : thibsdarts://join?h=192.168.1.20&p=8420&c=K7Q2
struct JoinLink {
    var host: String?
    var port = 8420
    var code: String

    init?(url: URL) {
        guard url.scheme == "thibsdarts", url.host == "join",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let c = items.first(where: { $0.name == "c" })?.value, c.count == 4 else { return nil }
        code = c.uppercased()
        host = items.first { $0.name == "h" }?.value
        port = Int(items.first { $0.name == "p" }?.value ?? "") ?? 8420
    }

    init(code: String) {
        self.code = code.uppercased()
    }
}

/// Client des salons du Pi (port 8420).
enum LobbyAPI {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        return URLSession(configuration: c)
    }()

    static func lobby(at base: URL) async throws -> LobbyInfo {
        let (data, res) = try await session.data(from: base.appendingPathComponent("api/lobby"))
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw PiError.unreachable }
        return try JSONDecoder().decode(LobbyInfo.self, from: data)
    }

    enum JoinError: LocalizedError {
        case code, closed, full, other(Int)

        var errorDescription: String? {
            switch self {
            case .code: "Ce code ne correspond à aucun salon. Regarde celui sous le QR code."
            case .closed: "Pas de salon ouvert. Demande à l’hôte d’en lancer un sur le Pi."
            case .full: "Le salon est complet, 8 joueurs max."
            case let .other(s): "Le Pi a répondu \(s)."
            }
        }
    }

    static func leave(at base: URL, id: String) async {
        var req = URLRequest(url: base.appendingPathComponent("api/lobby/leave"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id])
        _ = try? await session.data(for: req)
    }

    /// Arrête la partie en cours sur le Pi (retour à l'accueil, rien n'est enregistré).
    static func stop(at base: URL, id: String) async -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("api/lobby/stop"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id])
        guard let (_, res) = try? await session.data(for: req) else { return false }
        return (res as? HTTPURLResponse)?.statusCode == 200
    }

    static func photoURL(base: URL, player: LobbyPlayer) -> URL? {
        player.photo ? base.appendingPathComponent("api/players/\(player.id)/photo") : nil
    }
}


/// Réponse de /api/hello : sert à reconnaître une cible ThibsDarts sur le Wi-Fi.
struct PiHello: Decodable {
    let device: String
    let owner: String?
    /// Le propriétaire a choisi son code (absent sur les vieilles cibles).
    var pin: Bool?
}

extension LobbyAPI {
    static func hello(at base: URL, timeout: TimeInterval = 2) async -> PiHello? {
        var req = URLRequest(url: base.appendingPathComponent("api/hello"))
        req.timeoutInterval = timeout
        guard let (data, res) = try? await session.data(for: req),
              (res as? HTTPURLResponse)?.statusCode == 200,
              let h = try? JSONDecoder().decode(PiHello.self, from: data), h.device == "ThibsDarts"
        else { return nil }
        return h
    }
}
