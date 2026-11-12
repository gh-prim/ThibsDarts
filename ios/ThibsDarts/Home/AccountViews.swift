import AuthenticationServices
import CryptoKit
import SwiftUI

// Profils de la cible : chaque joueur a un profil sur le Pi (surnom, photo, code).
// L'appli s'y connecte avec le code et garde la clé donnée par le Pi.

// MARK: Pavé de code

/// 4 points et un pavé numérique. Appelle onComplete dès le 4e chiffre.
struct PinPad: View {
    let title: String
    var detail: String?
    var error: String?
    var busy = false
    let onComplete: (String) -> Void

    @State private var digits = ""
    @State private var shake = 0

    var body: some View {
        VStack(spacing: Td.s6) {
            VStack(spacing: Td.s2) {
                Text(title).font(.td(28, .bold)).tracking(-0.3).multilineTextAlignment(.center)
                // Hauteur fixe : le pavé ne bouge pas quand le texte change.
                Text(detail ?? " ").font(.td(15)).foregroundStyle(Td.ink2).multilineTextAlignment(.center)
                    .lineLimit(3, reservesSpace: true)
            }
            HStack(spacing: Td.s4) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < digits.count ? Td.sunset : .clear)
                        .overlay(Circle().strokeBorder(i < digits.count ? Td.sunset : Td.bordControle, lineWidth: 2))
                        .frame(width: 18, height: 18)
                }
            }
            .modifier(Shake(amount: CGFloat(shake)))
            .accessibilityElement()
            .accessibilityLabel("\(digits.count) chiffres sur 4")
            Group {
                if busy {
                    Spinner(size: 20)
                } else if let error {
                    Text(error).font(.td(15, .semibold)).foregroundStyle(Td.erreur).multilineTextAlignment(.center)
                } else {
                    Color.clear
                }
            }
            .frame(height: 40)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: Td.s4), count: 3), spacing: Td.s3) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "<"], id: \.self) { k in
                    key(k)
                }
            }
        }
        .onChange(of: error) { _, e in
            if e != nil { withAnimation(.default) { shake += 1 } }
        }
    }

    @ViewBuilder private func key(_ k: String) -> some View {
        if k.isEmpty {
            Color.clear.frame(width: 72, height: 72)
        } else {
            Button {
                tap(k)
            } label: {
                Group {
                    if k == "<" {
                        Icon(name: .chevronLeft, size: 24)
                    } else {
                        Text(k).font(.tdRounded(30, .bold))
                    }
                }
                .foregroundStyle(Td.ink)
                .frame(width: 72, height: 72)
                .background(Circle().fill(k == "<" ? .clear : Td.verreMoyen))
                .overlay(Circle().strokeBorder(k == "<" ? .clear : Td.verreBord))
            }
            .buttonStyle(PressScale())
            .disabled(busy)
            .accessibilityLabel(k == "<" ? "Effacer" : k)
        }
    }

    private func tap(_ k: String) {
        if k == "<" {
            if !digits.isEmpty { digits.removeLast() }
            return
        }
        guard digits.count < 4 else { return }
        digits.append(k)
        if digits.count == 4 {
            let pin = digits
            onComplete(pin)
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                digits = ""
            }
        }
    }
}

private struct Shake: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}

/// Choisir un code : on le tape deux fois.
struct PinChooser: View {
    let title: String
    var detail: String?
    var busy = false
    var serverError: String?
    let onDone: (String) -> Void

    @State private var first: String?
    @State private var mismatch = false

    var body: some View {
        PinPad(
            title: first == nil ? title : "Retape ton code",
            detail: first == nil ? detail : "Pour être sûr.",
            error: mismatch ? "Les deux codes ne sont pas pareils. On recommence." : serverError,
            busy: busy
        ) { pin in
            if let f = first {
                if f == pin {
                    mismatch = false
                    onDone(pin)
                } else {
                    mismatch = true
                    first = nil
                }
            } else {
                mismatch = false
                first = pin
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: API des profils

/// Un profil de la cible (GET /api/players).
struct PiPlayer: Decodable, Identifiable, Hashable {
    let id: String
    let nickname: String
    let owner: Bool
    /// Le profil a un code. Sans code : créé pour un pote sans appli, à réclamer.
    let pin: Bool
    let photo: Bool
}

enum ProfileError: LocalizedError {
    case wrong(Int?), locked(Int), taken, signedOut, other(Int)

    var errorDescription: String? {
        switch self {
        case let .wrong(left):
            if let left, left > 0, left < 3 { return "Mauvais code. Encore \(left) essai\(left > 1 ? "s" : "")." }
            return "Mauvais code."
        case let .locked(s): return "Trop d’essais. Réessaie dans \(s) secondes."
        case .taken: return "Ce surnom est déjà pris sur la cible."
        case .signedOut: return "Ta clé n’est plus reconnue par la cible. Déconnecte-toi puis reconnecte-toi avec ton code."
        case let .other(s): return "Le Pi a répondu \(s)."
        }
    }
}

extension LobbyAPI {
    struct SignIn: Decodable {
        let token: String
        let player: PiPlayer
    }

    static func players(at base: URL) async throws -> [PiPlayer] {
        struct List: Decodable { let players: [PiPlayer] }
        guard let (data, res) = try? await session.data(from: base.appendingPathComponent("api/players")),
              (res as? HTTPURLResponse)?.statusCode == 200 else { throw PiError.unreachable }
        return try JSONDecoder().decode(List.self, from: data).players
    }

    @MainActor
    private static func send(
        _ method: String, _ base: URL, _ path: String, json: [String: Any]? = nil, body: Data? = nil, app: AppModel? = nil
    ) async throws -> (Int, Data) {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if let body {
            req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        app?.authorize(&req)
        do {
            let (data, res) = try await session.data(for: req)
            return ((res as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw PiError.unreachable
        }
    }

    private static func signIn(_ status: Int, _ data: Data) throws -> SignIn {
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        switch status {
        case 200: return try JSONDecoder().decode(SignIn.self, from: data)
        case 403: throw ProfileError.wrong(j?["left"] as? Int)
        case 429: throw ProfileError.locked(j?["wait"] as? Int ?? 60)
        case 409 where j?["error"] as? String == "pris": throw ProfileError.taken
        case 401: throw ProfileError.signedOut
        default: throw ProfileError.other(status)
        }
    }

    /// Se connecter à son profil avec son code.
    @MainActor
    static func login(at base: URL, player: String, pin: String) async throws -> SignIn {
        let (s, d) = try await send("POST", base, "api/players/\(player)/login", json: ["pin": pin])
        return try signIn(s, d)
    }

    /// Réclamer un profil sans code (pote ajouté sans appli, ou vieille cible) en choisissant son code.
    @MainActor
    static func claim(at base: URL, player: String, pin: String) async throws -> SignIn {
        let (s, d) = try await send("POST", base, "api/players/\(player)/claim", json: ["pin": pin])
        return try signIn(s, d)
    }

    /// Nouveau profil. L'identifiant du téléphone est repris pour garder ses anciennes parties.
    @MainActor
    static func createProfile(at base: URL, nickname: String, pin: String, app: AppModel) async throws -> SignIn {
        let (s, d) = try await send(
            "POST", base, "api/players", json: ["nickname": nickname, "pin": pin, "id": app.deviceId]
        )
        return try signIn(s, d)
    }

    /// Le propriétaire ajoute un pote sans appli : un profil sans code.
    @MainActor
    static func addFriend(at base: URL, nickname: String, app: AppModel) async throws {
        let (s, d) = try await send("POST", base, "api/players", json: ["nickname": nickname], app: app)
        if s != 200 { _ = try signIn(s, d) }
    }

    /// Envoie le surnom et la photo du profil connecté à la cible.
    @MainActor
    static func syncProfile(app: AppModel) async throws {
        guard let base = app.piBase, let id = app.profileId else { return }
        let (s, d) = try await send("PATCH", base, "api/players/\(id)", json: ["nickname": app.nickname], app: app)
        if s != 200 { _ = try signIn(s, d) }
        if let jpeg = app.photoJpeg {
            let (s, d) = try await send("PUT", base, "api/players/\(id)/photo", body: jpeg, app: app)
            if s != 200 { _ = try signIn(s, d) }
        }
    }

    static func profilePhoto(at base: URL, id: String) async -> UIImage? {
        guard let (data, res) = try? await session.data(from: base.appendingPathComponent("api/players/\(id)/photo")),
              (res as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }
}

// MARK: Trouver la cible

/// On cherche les cibles sur le Wi-Fi. Une seule : on la prend.
struct CibleFinder: View {
    let onBack: () -> Void
    let onFound: (URL) -> Void

    @State private var found: [FoundPi] = []
    @State private var searching = true

    var body: some View {
        Stage {
            VStack(spacing: Td.s4) {
                NavBar(title: "Ta cible", back: "Retour", onBack: onBack)
                if searching {
                    VStack(spacing: Td.s3) {
                        Spinner(size: 32)
                        Text("On cherche la cible sur le Wi-Fi.").font(.td(17, .semibold))
                        Text("Reste sur le même Wi-Fi que la cible.").font(.td(15)).foregroundStyle(Td.ink2)
                    }
                    .frame(maxHeight: .infinity)
                } else if found.isEmpty {
                    VStack(spacing: Td.s4) {
                        ChartState(icon: .wifiOff, text: "Aucune cible trouvée. Mets ton iPhone sur le Wi-Fi de la cible.")
                        TdButton(title: "Chercher encore", variant: .secondary, icon: .refreshCw, block: true) {
                            Task { await search() }
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: Td.s3) {
                        ObHeader(title: "Quelle cible ?", detail: "Celle où tu joues.")
                        ForEach(found) { pi in
                            Button { onFound(pi.base) } label: {
                                Row(icon: .target, title: "Cible de \(pi.owner)")
                            }
                            .buttonStyle(PressScale())
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
            .padding(.bottom, Td.s5)
        }
        .task { await search() }
    }

    private func search() async {
        searching = true
        // Au premier lancement, iOS demande l'accès au réseau local : tant que la
        // question est affichée, tout échoue. On réessaie donc quelques fois.
        for attempt in 0..<4 {
            found = await Discovery.scan()
            if !found.isEmpty || Task.isCancelled { break }
            if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
        }
        searching = false
        if found.count == 1 { onFound(found[0].base) }
    }
}

/// Ligne touchable : icône ou photo, titre, détail, chevron.
private struct Row<Lead: View>: View {
    let lead: Lead
    let title: String
    var detail: String?

    init(icon: LucideIcon, title: String, detail: String? = nil) where Lead == AnyView {
        lead = AnyView(Icon(name: icon, size: 20).foregroundStyle(Td.sunset))
        self.title = title
        self.detail = detail
    }

    init(title: String, detail: String? = nil, @ViewBuilder lead: () -> Lead) {
        self.lead = lead()
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: Td.s3) {
            lead
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.td(17, .semibold))
                if let detail { Text(detail).font(.td(13)).foregroundStyle(Td.ink2) }
            }
            Spacer()
            Icon(name: .chevronRight, size: 18).foregroundStyle(Td.ink3)
        }
        .foregroundStyle(Td.ink)
        .padding(Td.s4)
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.asphalte))
        .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.bord))
    }
}

// MARK: Qui es-tu ?

/// Les profils de la cible : on choisit le sien et on tape son code, ou on en crée un.
struct WhoView: View {
    @EnvironmentObject var app: AppModel
    let base: URL
    let onBack: () -> Void
    let onNew: () -> Void

    @State private var players: [PiPlayer]?
    @State private var chosen: PiPlayer?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Stage {
            VStack(spacing: Td.s4) {
                NavBar(title: chosen == nil ? "" : chosen!.nickname, back: "Retour") {
                    if chosen != nil { chosen = nil; error = nil } else { onBack() }
                }
                if let chosen {
                    if chosen.pin {
                        PinPad(title: "Ton code", detail: "Les 4 chiffres de ton profil.", error: error, busy: busy) {
                            signIn(chosen, $0, claim: false)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        PinChooser(
                            title: "Choisis ton code",
                            detail: "4 chiffres pour retrouver ton profil sur n’importe quel iPhone.",
                            busy: busy, serverError: error
                        ) { signIn(chosen, $0, claim: true) }
                    }
                } else if let players {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Td.s3) {
                            ObHeader(title: "C’est qui ?", detail: "Choisis ton profil sur la cible.")
                            ForEach(players) { p in
                                Button { chosen = p } label: {
                                    Row(title: p.nickname, detail: p.owner ? (p.pin ? "Propriétaire" : "Propriétaire, sans code") : (p.pin ? nil : "Sans code")) {
                                        Avatar(name: p.nickname, url: p.photo ? base.appendingPathComponent("api/players/\(p.id)/photo") : nil, size: 40)
                                    }
                                }
                                .buttonStyle(PressScale())
                            }
                            if let error { Banner(text: error, error: true) }
                        }
                    }
                    TdButton(title: "Je suis nouveau", icon: .plus, block: true, action: onNew)
                } else {
                    VStack(spacing: Td.s4) {
                        if let error {
                            ChartState(icon: .wifiOff, text: error)
                            TdButton(title: "Réessayer", variant: .secondary, icon: .refreshCw, block: true) {
                                Task { await load() }
                            }
                        } else {
                            Spinner(size: 32)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
            .padding(.bottom, Td.s5)
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            players = try await LobbyAPI.players(at: base)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func signIn(_ p: PiPlayer, _ pin: String, claim: Bool) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let r = claim
                    ? try await LobbyAPI.claim(at: base, player: p.id, pin: pin)
                    : try await LobbyAPI.login(at: base, player: p.id, pin: pin)
                let photo = r.player.photo ? await LobbyAPI.profilePhoto(at: base, id: r.player.id) : nil
                app.signIn(r.player, token: r.token, base: base, photo: photo)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Nouveau profil : surnom et photo (déjà saisis), puis le code, puis on l'envoie à la cible.
struct NewProfilePinView: View {
    @EnvironmentObject var app: AppModel
    let base: URL
    let onBack: () -> Void

    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Stage {
            VStack(spacing: Td.s4) {
                NavBar(title: "", back: "Profil", onBack: onBack)
                PinChooser(
                    title: "Choisis ton code",
                    detail: "4 chiffres pour retrouver ton profil sur n’importe quel iPhone.",
                    busy: busy, serverError: error
                ) { create($0) }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
            .padding(.bottom, Td.s5)
        }
    }

    private func create(_ pin: String) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let r = try await LobbyAPI.createProfile(at: base, nickname: app.nickname, pin: pin, app: app)
                app.signIn(r.player, token: r.token, base: base, photo: app.photo)
                try? await LobbyAPI.syncProfile(app: app)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Le propriétaire ajoute un pote sans appli. Il pourra réclamer son profil plus tard.
struct AddFriendView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Stage {
            VStack(alignment: .leading, spacing: Td.s4) {
                NavBar(title: "Ajouter un joueur", back: "Profil") { dismiss() }
                ObHeader(title: "Un pote sans appli", detail: "Il apparaît sur la cible. S’il installe l’appli, il choisit son code et garde ses parties.")
                Field(label: "Son surnom", text: $name, placeholder: "Lou", icon: .user, contentType: .nickname)
                if let error { Banner(text: error, error: true) }
                Spacer()
                TdButton(
                    title: "Ajouter", icon: .plus, block: true,
                    state: busy ? .loading : (name.trimmingCharacters(in: .whitespaces).isEmpty ? .disabled : .normal)
                ) { add() }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
            .padding(.bottom, Td.s5)
        }
    }

    private func add() {
        guard let base = app.piBase else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await LobbyAPI.addFriend(at: base, nickname: name.trimmingCharacters(in: .whitespaces), app: app)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: Spotify

/// App développeur Spotify de ThibsDarts (developer.spotify.com), redirection thibsdarts://spotify-callback.
enum SpotifyConfig {
    static let clientID = "dddb74e15eab43e4b275995dffd6d0bd"
    static let redirect = "thibsdarts://spotify-callback"
    static let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing"
}

/// Connexion Spotify sur l'iPhone (PKCE, sans secret). Le jeton de rafraîchissement part sur le Pi.
@MainActor
final class SpotifyAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Failure: LocalizedError {
        case config, cancelled, token
        var errorDescription: String? {
            switch self {
            case .config: "Spotify n’est pas encore configuré dans l’app."
            case .cancelled: "Connexion Spotify annulée."
            case .token: "Spotify a refusé la connexion."
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    func refreshToken() async throws -> String {
        guard !SpotifyConfig.clientID.isEmpty else { throw Failure.config }
        let verifier = Self.random(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: SpotifyConfig.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: SpotifyConfig.redirect),
            .init(name: "scope", value: SpotifyConfig.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "thibsdarts") { url, error in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: error ?? Failure.cancelled) }
            }
            s.presentationContextProvider = self
            session = s
            s.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { throw Failure.cancelled }

        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code", value: code),
            .init(name: "redirect_uri", value: SpotifyConfig.redirect),
            .init(name: "client_id", value: SpotifyConfig.clientID),
            .init(name: "code_verifier", value: verifier),
        ]
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200,
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let refresh = j["refresh_token"] as? String else { throw Failure.token }
        return refresh
    }

    private static func random(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension LobbyAPI {
    /// Relie le compte Spotify au Pi (propriétaire uniquement).
    @MainActor
    static func linkSpotify(refreshToken: String, app: AppModel) async throws {
        guard let base = app.piBase else { throw PiError.unreachable }
        let (status, _) = try await send(
            "POST", base, "api/spotify/link", json: ["clientId": SpotifyConfig.clientID, "refreshToken": refreshToken], app: app
        )
        guard status == 200 else { throw PiError.http(status, "Spotify") }
    }
}
