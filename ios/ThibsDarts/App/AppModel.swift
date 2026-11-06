import SwiftUI
import UIKit

/// Profil du joueur sur ce téléphone, et le ThibsDarts qu'il connaît.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var nickname: String
    @Published private(set) var firstName: String
    @Published private(set) var lastName: String
    @Published private(set) var photo: UIImage?
    @Published var notify: Bool {
        didSet { defaults.set(notify, forKey: "notify") }
    }

    /// Ce téléphone a installé la cible : il est l'hôte de son salon.
    @Published private(set) var isOwner: Bool

    /// Adresse du Pi, apprise au setup ou au scan d'un salon.
    @Published private(set) var piBase: URL?

    /// Le joueur a fini l'accueil (profil puis installation ou premier salon).
    @Published var onboarded: Bool {
        didSet { defaults.set(onboarded, forKey: "onboarded") }
    }

    /// Salon rejoint en ce moment.
    @Published var lobby: ActiveLobby?

    let deviceId: String
    private let defaults = UserDefaults.standard

    var hasProfile: Bool { !nickname.isEmpty && photo != nil }

    private static var photoURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("profile.jpg")
    }

    init() {
        nickname = defaults.string(forKey: "nickname") ?? ""
        firstName = defaults.string(forKey: "firstName") ?? ""
        lastName = defaults.string(forKey: "lastName") ?? ""
        notify = defaults.object(forKey: "notify") as? Bool ?? true
        isOwner = defaults.bool(forKey: "isOwner")
        piBase = defaults.url(forKey: "piBase")
        onboarded = defaults.bool(forKey: "onboarded")
        if let id = defaults.string(forKey: "deviceId") {
            deviceId = id
        } else {
            deviceId = UUID().uuidString
            defaults.set(deviceId, forKey: "deviceId")
        }
        photo = (try? Data(contentsOf: Self.photoURL)).flatMap(UIImage.init(data:))
    }

    func saveProfile(nickname: String, firstName: String? = nil, lastName: String? = nil, photo: UIImage?) {
        self.nickname = nickname.trimmingCharacters(in: .whitespaces)
        defaults.set(self.nickname, forKey: "nickname")
        if let firstName {
            self.firstName = firstName
            defaults.set(firstName, forKey: "firstName")
        }
        if let lastName {
            self.lastName = lastName
            defaults.set(lastName, forKey: "lastName")
        }
        if let photo, let data = SetupModel.squareJpeg(photo) {
            try? data.write(to: Self.photoURL, options: .atomic)
            self.photo = UIImage(data: data)
        }
    }

    func setOwner(piBase: URL?) {
        isOwner = true
        defaults.set(true, forKey: "isOwner")
        remember(piBase: piBase)
    }

    func remember(piBase: URL?) {
        guard let piBase else { return }
        self.piBase = piBase
        defaults.set(piBase, forKey: "piBase")
    }

    var photoJpeg: Data? { photo.flatMap(SetupModel.squareJpeg) }

    func enter(lobby info: LobbyInfo, base: URL) {
        remember(piBase: base)
        lobby = ActiveLobby(base: base, info: info)
        onboarded = true
    }
}

struct ActiveLobby: Identifiable {
    let base: URL
    var info: LobbyInfo
    var id: String { base.absoluteString + (info.you ?? "") }
}

// MARK: Salon

struct LobbyPlayer: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let host: Bool
    let guest: Bool
    let photo: Bool
    let connected: Bool
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
    private static let session: URLSession = {
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

    @MainActor
    static func join(at base: URL, code: String, app: AppModel) async throws -> LobbyInfo {
        var req = URLRequest(url: base.appendingPathComponent("api/lobby/join"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "code": code, "id": app.deviceId, "name": app.nickname, "owner": app.isOwner,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, res) = try await session.data(for: req)
        switch (res as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 403: throw JoinError.code
        case 409: throw JoinError.closed
        case 410: throw JoinError.full
        case let s: throw JoinError.other(s)
        }
        let info = try JSONDecoder().decode(LobbyInfo.self, from: data)
        if let you = info.you, let jpeg = app.photoJpeg, !app.isOwner {
            var up = URLRequest(url: base.appendingPathComponent("api/players/\(you)/photo"))
            up.httpMethod = "PUT"
            up.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            up.httpBody = jpeg
            _ = try? await session.data(for: up)
        }
        return info
    }

    static func leave(at base: URL, id: String) async {
        var req = URLRequest(url: base.appendingPathComponent("api/lobby/leave"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id])
        _ = try? await session.data(for: req)
    }

    static func photoURL(base: URL, player: LobbyPlayer) -> URL? {
        player.photo ? base.appendingPathComponent("api/players/\(player.id)/photo") : nil
    }
}
