import SwiftUI

/// Créer une partie depuis l'iPhone (planche Nouvelle partie) : le salon s'ouvre sur l'écran du Pi.
struct NewGameView: View {
    @EnvironmentObject var app: AppModel
    var onBack: () -> Void
    /// Salon ouvert : on y entre une fois cet écran fermé.
    var onCreated: (LobbyInfo, URL) -> Void

    struct Mode: Identifiable {
        let id: String
        let glyph: String
        let title: String
        var rule: String?
        var playable = true
    }

    static let modes = [
        Mode(id: "301", glyph: "301", title: "Le sprint"),
        Mode(id: "501", glyph: "501", title: "Le classique"),
        Mode(id: "cricket", glyph: "15+", title: "Cricket",
             rule: "Ferme 20 à 15 et le bull en 3 marques. Ce que tu fermes avant les autres te rapporte des points."),
        Mode(id: "clock", glyph: "1>20", title: "Clock",
             rule: "Touche 1, 2, 3, jusqu’à 20, dans l’ordre. Simple, double ou triple, tout compte."),
        Mode(id: "shanghai", glyph: "S·D·T", title: "Shanghai",
             rule: "7 manches. Manche 1 on vise le 1, puis le 2... Simple, double et triple au même tour : gagné."),
        Mode(id: "killer", glyph: "K", title: "Killer",
             rule: "Chacun reçoit un numéro et 3 vies. Ton double te rend killer, puis tu chasses les doubles des autres."),
        Mode(id: "halveIt", glyph: "½", title: "Halve-it",
             rule: "9 cibles imposées, départ à 40. Rien touché au tour : ton score est divisé par deux."),
        Mode(id: "bobs27", glyph: "27", title: "Bob’s 27",
             rule: "Départ à 27, de D1 à D20 puis bull. Un double rapporte sa valeur, un tour à vide la coûte."),
        Mode(id: "training", glyph: "T20", title: "Entraînement", playable: false),
    ]

    @State private var mode = "501"
    @State private var out = "Double"
    @State private var legs = 2
    @State private var busy = false
    @State private var error: String?

    private var current: Mode { Self.modes.first { $0.id == mode }! }
    private var isX01: Bool { mode == "301" || mode == "501" }

    var body: some View {
        Stage {
            VStack(alignment: .leading, spacing: 14) {
                NavBar(title: "Nouvelle partie", back: "Jouer", onBack: onBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        label("Mode")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Td.s2), count: 3), spacing: Td.s2) {
                            ForEach(Self.modes) { m in
                                ModeTile(mode: m, selected: m.id == mode) {
                                    if m.playable {
                                        withAnimation(Td.sortie) { mode = m.id }
                                    } else {
                                        error = "\(m.title) arrive bientôt."
                                    }
                                }
                            }
                        }
                        if isX01 {
                            label("Sortie").padding(.top, Td.s1)
                            SegmentedControl(options: ["Double", "Simple"], value: $out)
                            HStack {
                                Text("Manches gagnantes").font(.td(15, .semibold))
                                Spacer()
                                TdStepper(value: $legs, range: 1...5)
                            }
                        } else if let rule = current.rule {
                            Text(rule).font(.td(15)).foregroundStyle(Td.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let error { Banner(text: error, error: true) }
                    }
                }
                Text(app.piBase == nil
                     ? "Scanne d’abord le QR code d’un salon pour relier ton iPhone à la cible."
                     : "Le salon s’ouvre sur l’écran du Pi. Les autres le rejoignent avec le QR code.")
                    .font(.td(13)).foregroundStyle(Td.ink3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                TdButton(title: "Ouvrir le salon", icon: .play, block: true,
                         state: busy ? .loading : (app.piBase == nil ? .disabled : .normal)) { create() }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, Td.s2)
            .padding(.bottom, Td.s5)
        }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.td(13, .semibold)).foregroundStyle(Td.ink2)
    }

    private func create() {
        guard let base = app.piBase, !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let info = try await LobbyAPI.create(
                    at: base, mode: mode, doubleOut: out == "Double", legsToWin: legs, app: app
                )
                onCreated(info, base)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Tuile de mode (ModeTile) : gros glyphe, titre ; orange quand elle est choisie.
struct ModeTile: View {
    let mode: NewGameView.Mode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Td.s3) {
                Text(mode.glyph)
                    .font(.tdRounded(40, .black)).tracking(-1)
                    .foregroundStyle(!mode.playable ? Td.desactiveInk : (selected ? Td.sunset : Td.ink))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                Text(mode.title).font(.td(15, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(mode.playable ? Td.ink : Td.desactiveInk)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .padding(Td.s3)
            .background(
                RoundedRectangle(cornerRadius: Td.rXl)
                    .fill(!mode.playable ? Td.desactiveFond : (selected ? Td.sunsetFond : Td.verreMoyen))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Td.rXl)
                    .strokeBorder(!mode.playable ? .clear : (selected ? Td.sunset : Td.verreBord))
            )
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(mode.playable ? mode.title : "\(mode.title), bientôt")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Moins, valeur, plus (Stepper).
struct TdStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: Td.s2) {
            round("−", label: "Moins", enabled: value > range.lowerBound) { value -= 1 }
            Text("\(value)").font(.tdRounded(28, .heavy)).monospacedDigit().frame(minWidth: 56)
            round("+", label: "Plus", enabled: value < range.upperBound) { value += 1 }
        }
        .accessibilityElement(children: .contain)
    }

    private func round(_ t: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.td(22, .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(enabled ? Td.ink : Td.desactiveInk)
                .background(Circle().fill(Td.verreMoyen))
                .overlay(Circle().strokeBorder(Td.verreBord))
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

extension LobbyAPI {
    enum CreateError: LocalizedError {
        case playing, open, busy, other(Int)

        var errorDescription: String? {
            switch self {
            case .playing: "Une partie est déjà en cours sur la cible."
            case .open: "Un salon est déjà ouvert. Rejoins-le depuis l’accueil."
            case .busy: "L’écran de la cible est occupé. Reviens à son accueil et réessaie."
            case let .other(s): "Le Pi a répondu \(s)."
            }
        }
    }

    @MainActor
    static func create(at base: URL, mode: String, doubleOut: Bool, legsToWin: Int, app: AppModel) async throws -> LobbyInfo {
        var req = URLRequest(url: base.appendingPathComponent("api/lobby/create"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "id": app.deviceId, "name": app.nickname, "owner": app.isOwner,
            "mode": mode, "doubleOut": doubleOut, "legsToWin": legsToWin,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, res: URLResponse
        do {
            (data, res) = try await session.data(for: req)
        } catch {
            throw PiError.unreachable
        }
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        if status == 409 {
            let err = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            switch err {
            case "en_cours": throw CreateError.playing
            case "ouvert": throw CreateError.open
            default: throw CreateError.busy
            }
        }
        guard status == 200 else { throw CreateError.other(status) }
        let info = try JSONDecoder().decode(LobbyInfo.self, from: data)
        await uploadPhoto(at: base, info: info, app: app)
        return info
    }

    /// Envoie la photo du profil au Pi pour un pote (le propriétaire a déjà la sienne).
    @MainActor
    static func uploadPhoto(at base: URL, info: LobbyInfo, app: AppModel) async {
        guard let you = info.you, let jpeg = app.photoJpeg, !app.isOwner else { return }
        var up = URLRequest(url: base.appendingPathComponent("api/players/\(you)/photo"))
        up.httpMethod = "PUT"
        up.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        up.httpBody = jpeg
        _ = try? await session.data(for: up)
    }
}
