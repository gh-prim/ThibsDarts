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

    /// Le profil connecté est le propriétaire de la cible : il est l'hôte de son salon.
    @Published private(set) var isOwner: Bool

    /// Profil de la cible auquel ce téléphone est connecté, et sa clé (donnée par le Pi après le code).
    @Published private(set) var profileId: String?
    private(set) var token: String?

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
    var signedIn: Bool { profileId != nil && token != nil }

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
        profileId = defaults.string(forKey: "playerId")
        token = defaults.string(forKey: "playerToken")
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

    /// Connecté à un profil de la cible avec son code (ou à la fin du setup pour le propriétaire).
    func signIn(_ player: PiPlayer, token: String, base: URL, photo: UIImage?, onboard: Bool = true) {
        profileId = player.id
        self.token = token
        isOwner = player.owner
        defaults.set(player.id, forKey: "playerId")
        defaults.set(token, forKey: "playerToken")
        defaults.set(player.owner, forKey: "isOwner")
        remember(piBase: base)
        saveProfile(nickname: player.nickname, photo: photo)
        if onboard { onboarded = true }
    }

    func remember(piBase: URL?) {
        guard let piBase else { return }
        self.piBase = piBase
        defaults.set(piBase, forKey: "piBase")
    }

    var photoJpeg: Data? { photo.flatMap(SetupModel.squareJpeg) }

    /// Se déconnecter : on oublie le profil et la cible. L'identifiant du téléphone reste.
    func logout() {
        lobby = nil
        for key in ["nickname", "firstName", "lastName", "isOwner", "piBase", "onboarded", "playerId", "playerToken"] {
            defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: Self.photoURL)
        nickname = ""
        firstName = ""
        lastName = ""
        photo = nil
        isOwner = false
        profileId = nil
        token = nil
        piBase = nil
        onboarded = false
    }

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


extension LobbyAPI {
    @MainActor
    static func join(at base: URL, code: String, app: AppModel) async throws -> LobbyInfo {
        var req = URLRequest(url: base.appendingPathComponent("api/lobby/join"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        app.authorize(&req)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "player": app.playerId])
        let (data, res) = try await session.data(for: req)
        switch (res as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401: throw ProfileError.signedOut
        case 403: throw JoinError.code
        case 409: throw JoinError.closed
        case 410: throw JoinError.full
        case let s: throw JoinError.other(s)
        }
        return try JSONDecoder().decode(LobbyInfo.self, from: data)
    }
}

extension AppModel {
    /// Ajoute la clé du profil à une requête vers le Pi.
    func authorize(_ req: inout URLRequest) {
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }
}
