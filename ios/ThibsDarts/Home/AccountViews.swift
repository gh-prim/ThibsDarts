import SwiftUI

// Compte : code PIN du propriétaire, déconnexion, reconnexion en propriétaire.

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

// MARK: API du compte

extension LobbyAPI {
    struct OwnerProfile: Decodable {
        let firstName: String
        let lastName: String
        let nickname: String
        let photo: Bool
    }

    enum PinError: LocalizedError {
        case wrong(Int?), locked(Int), noPin, other(Int)

        var errorDescription: String? {
            switch self {
            case let .wrong(left):
                if let left, left > 0, left < 3 { return "Mauvais code. Encore \(left) essai\(left > 1 ? "s" : "")." }
                return "Mauvais code."
            case let .locked(s): return "Trop d’essais. Réessaie dans \(s) secondes."
            case .noPin: return "Cette cible n’a pas encore de code. Ouvre l’appli sur l’iPhone du propriétaire."
            case let .other(s): return "Le Pi a répondu \(s)."
            }
        }
    }

    private static func postPin(_ base: URL, _ path: String, _ pin: String) async throws -> (Int, Data) {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["pin": pin])
        do {
            let (data, res) = try await session.data(for: req)
            return ((res as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw PiError.unreachable
        }
    }

    static func ownerLogin(at base: URL, pin: String) async throws -> OwnerProfile {
        let (status, data) = try await postPin(base, "api/owner/login", pin)
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        switch status {
        case 200: return try JSONDecoder().decode(OwnerProfile.self, from: data)
        case 403: throw PinError.wrong(j?["left"] as? Int)
        case 429: throw PinError.locked(j?["wait"] as? Int ?? 60)
        case 409: throw PinError.noPin
        default: throw PinError.other(status)
        }
    }

    static func setOwnerPin(at base: URL, pin: String) async throws {
        let (status, _) = try await postPin(base, "api/owner/pin", pin)
        // 409 : un code existe déjà (choisi depuis un autre iPhone), rien à faire.
        guard status == 200 || status == 409 else { throw PinError.other(status) }
    }

    static func ownerPhoto(at base: URL) async -> UIImage? {
        guard let (data, res) = try? await session.data(from: base.appendingPathComponent("api/owner/photo")),
              (res as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }
}

// MARK: Reconnexion du propriétaire

/// "C'est ma cible" : on trouve la cible sur le Wi-Fi, puis le code du propriétaire.
struct OwnerLoginView: View {
    @EnvironmentObject var app: AppModel
    let onBack: () -> Void

    @State private var found: [FoundPi] = []
    @State private var searching = true
    @State private var chosen: FoundPi?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Stage {
            VStack(spacing: Td.s4) {
                NavBar(title: "Propriétaire", back: "Retour") {
                    if chosen != nil && found.count > 1 { chosen = nil } else { onBack() }
                }
                if let chosen {
                    PinPad(
                        title: "Ton code",
                        detail: "Les 4 chiffres choisis à l’installation de la cible de \(chosen.owner).",
                        error: error, busy: busy
                    ) { login(chosen, $0) }
                    .frame(maxHeight: .infinity)
                } else if searching {
                    VStack(spacing: Td.s3) {
                        Spinner(size: 32)
                        Text("On cherche ta cible sur le Wi-Fi.").font(.td(17, .semibold))
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
                        ObHeader(title: "Quelle cible ?", detail: "Choisis la tienne.")
                        ForEach(found) { pi in
                            Button { chosen = pi } label: {
                                HStack(spacing: Td.s3) {
                                    Icon(name: .target, size: 20).foregroundStyle(Td.sunset)
                                    Text("Cible de \(pi.owner)").font(.td(17, .semibold))
                                    Spacer()
                                    Icon(name: .chevronRight, size: 18).foregroundStyle(Td.ink3)
                                }
                                .padding(Td.s4)
                                .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.asphalte))
                                .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.bord))
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
        found = await Discovery.scan()
        searching = false
        if found.count == 1 { chosen = found[0] }
    }

    private func login(_ pi: FoundPi, _ pin: String) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let p = try await LobbyAPI.ownerLogin(at: pi.base, pin: pin)
                let photo = p.photo ? await LobbyAPI.ownerPhoto(at: pi.base) : nil
                app.restoreOwner(p, photo: photo, piBase: pi.base)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Cible installée avant le code : le propriétaire le choisit à l'ouverture de l'appli.
struct OwnerPinSetupView: View {
    @EnvironmentObject var app: AppModel
    let base: URL
    let onDone: () -> Void

    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Stage {
            PinChooser(
                title: "Choisis ton code",
                detail: "Nouveau : 4 chiffres pour te reconnaître comme propriétaire de la cible, même sur un autre iPhone.",
                busy: busy, serverError: error
            ) { pin in
                busy = true
                error = nil
                Task {
                    defer { busy = false }
                    do {
                        try await LobbyAPI.setOwnerPin(at: base, pin: pin)
                        onDone()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
            .padding(.horizontal, Td.s4)
        }
        .interactiveDismissDisabled()
    }
}

// MARK: Déconnexion

extension AppModel {
    /// Reconnecté en propriétaire avec son code : profil et cible repris du Pi.
    func restoreOwner(_ p: LobbyAPI.OwnerProfile, photo: UIImage?, piBase: URL) {
        saveProfile(nickname: p.nickname, firstName: p.firstName, lastName: p.lastName, photo: photo)
        setOwner(piBase: piBase)
        onboarded = true
    }
}
