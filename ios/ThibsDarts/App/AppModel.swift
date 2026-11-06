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


extension LobbyAPI {
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
        await uploadPhoto(at: base, info: info, app: app)
        return info
    }

}
