import SwiftUI

/// Tournoi depuis l'iPhone : inscriptions (planche Nouveau tournoi) puis tirage (planche Tirage au sort).
/// L'écran suit le tournoi du Pi : il passe tout seul au tirage quand l'organisateur l'a fait.
struct TournamentFlow: View {
    @EnvironmentObject var app: AppModel
    let base: URL
    var onClose: () -> Void

    @State private var info: TournamentInfo?
    @State private var loaded = false

    var body: some View {
        Group {
            if let info, info.state == "tirage" {
                TournamentDrawView(base: base, info: info, onUpdate: { self.info = $0 }, onBack: onClose)
            } else if let info, info.state == "inscriptions" {
                TournamentCreateView(base: base, info: info, onUpdate: { self.info = $0 }, onBack: onClose)
            } else {
                Stage {
                    VStack(spacing: Td.s4) {
                        NavBar(title: info?.name ?? "Tournoi", back: "Jouer", onBack: onClose)
                        Spacer()
                        if loaded {
                            EmptyState(icon: .trophy, text: info == nil
                                       ? "Pas de tournoi sur la cible."
                                       : "Le tournoi est lancé. Le tableau arrive bientôt sur l’iPhone.")
                        } else {
                            Spinner(size: 28)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Td.s4)
                    .padding(.top, Td.s2)
                }
            }
        }
        .task { await poll() }
    }

    private func poll() async {
        while !Task.isCancelled {
            if let t = try? await LobbyAPI.tournament(at: base) { info = t }
            loaded = true
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

/// Nouveau tournoi : mode, manches gagnantes, inscrits. L'organisateur fait le tirage.
struct TournamentCreateView: View {
    @EnvironmentObject var app: AppModel
    let base: URL
    let info: TournamentInfo
    var onUpdate: (TournamentInfo?) -> Void
    var onBack: () -> Void

    @State private var mode = "501"
    @State private var legs = 3
    @State private var busy = false
    @State private var error: String?
    @State private var picking = false
    @State private var removing: TournamentPlayer?
    @State private var cancelling = false

    private var boss: Bool { app.playerId == info.organizer || app.isOwner }
    private var inside: Bool { info.entrants.contains { $0.id == app.playerId } }

    var body: some View {
        Stage {
            VStack(alignment: .leading, spacing: 14) {
                NavBar(title: "Nouveau tournoi", back: "Jouer", onBack: onBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        label("Mode")
                        SegmentedControl(options: ["501", "301", "Cricket"], value: $mode)
                            .disabled(!boss)
                        if mode == "Cricket" {
                            Text("Au Cricket, chaque match se joue en une manche.")
                                .font(.td(15)).foregroundStyle(Td.ink2)
                        } else {
                            HStack {
                                Text("Manches gagnantes").font(.td(15, .semibold))
                                Spacer()
                                TdStepper(value: $legs, range: 1...5).disabled(!boss)
                            }
                        }
                        HStack(alignment: .firstTextBaseline) {
                            label("Inscrits")
                            Spacer()
                            Text("\(info.entrants.count) sur \(info.max)")
                                .font(.td(13, .semibold)).foregroundStyle(Td.sunset)
                        }
                        entrants
                        if let error { Banner(text: error, error: true) }
                    }
                }
                Text("Les autres s’inscrivent depuis l’onglet Jouer de leur appli. Une place vide donne un match gratuit.")
                    .font(.td(13)).foregroundStyle(Td.ink3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if boss {
                    TdButton(title: "Faire le tirage au sort", icon: .users, block: true,
                             state: busy ? .loading : (info.entrants.count < 3 ? .disabled : .normal)) {
                        send("draw")
                    }
                    TdButton(title: "Annuler le tournoi", variant: .tertiary, size: .sm, block: true) { cancelling = true }
                } else {
                    TdButton(title: inside ? "Me désinscrire" : "M’inscrire",
                             variant: inside ? .secondary : .primary,
                             icon: inside ? .x : .plus, block: true, state: busy ? .loading : .normal) {
                        send(inside ? "remove" : "join")
                    }
                }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, Td.s2)
            .padding(.bottom, Td.s5)
        }
        .onAppear {
            mode = info.modeLabel
            legs = info.legsToWin
        }
        .onChange(of: info.mode) { mode = info.modeLabel }
        .onChange(of: info.legsToWin) { legs = info.legsToWin }
        .onChange(of: mode) { if boss && mode != info.modeLabel { settings() } }
        .onChange(of: legs) { if boss && legs != info.legsToWin { settings() } }
        .sheet(isPresented: $picking) {
            TournamentPickPlayer(base: base, taken: Set(info.entrants.map(\.id)), onGuest: { name in
                picking = false
                send("guest", ["name": name])
            }) { p in
                picking = false
                send("add", ["id": p.id])
            }
            .environmentObject(app)
            .presentationDetents([.medium, .large])
            .presentationBackground(Td.beton)
        }
        .confirmationDialog("Retirer \(removing?.name ?? "") du tournoi ?", isPresented: .init(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible) {
            Button("Retirer", role: .destructive) {
                if let p = removing { send("remove", ["id": p.id]) }
            }
        }
        .confirmationDialog("Annuler le tournoi ?", isPresented: $cancelling, titleVisibility: .visible) {
            Button("Annuler le tournoi", role: .destructive) { send("cancel") }
            Button("Garder", role: .cancel) {}
        }
    }

    private var entrants: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Td.s2), count: 4), spacing: Td.s3) {
            ForEach(info.entrants) { p in
                Button {
                    if boss && p.id != app.playerId { removing = p }
                } label: {
                    VStack(spacing: Td.s1) {
                        Avatar(name: p.name, url: p.photoURL(base: base), size: 44)
                        Text(p.name).font(.td(12)).foregroundStyle(Td.ink2).lineLimit(1)
                    }
                }
                .buttonStyle(PressScale())
                .accessibilityLabel(p.name)
            }
            if info.entrants.count < info.max {
                Button { if boss { picking = true } } label: {
                    VStack(spacing: Td.s1) {
                        Circle().strokeBorder(Td.bordControle, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                            .frame(width: 44, height: 44)
                            .overlay { if boss { Icon(name: .plus, size: 20).foregroundStyle(Td.ink3) } }
                        Text("Libre").font(.td(12)).foregroundStyle(Td.ink3)
                    }
                }
                .buttonStyle(PressScale())
                .accessibilityLabel(boss ? "Ajouter un joueur" : "Place libre")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, Td.s3)
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.verreLeger))
        .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.verreBord))
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.td(13, .semibold)).foregroundStyle(Td.ink2)
    }

    private func settings() {
        send("settings", ["mode": mode == "Cricket" ? "cricket" : mode, "legsToWin": legs])
    }

    private func send(_ action: String, _ extra: [String: Any] = [:]) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                onUpdate(try await LobbyAPI.tournamentAction(action, at: base, app: app, extra))
                if action == "cancel" { onBack() }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Ajouter un joueur au tournoi : les profils de la cible pas encore inscrits.
private struct TournamentPickPlayer: View {
    let base: URL
    let taken: Set<String>
    /// Invité sans profil : juste un nom.
    var onGuest: (String) -> Void
    var onPick: (PiPlayer) -> Void
    @State private var players: [PiPlayer]?
    @State private var guest = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Td.s3) {
            Text("Ajouter un joueur").font(.td(17, .semibold)).frame(maxWidth: .infinity).padding(.top, Td.s5)
            HStack(alignment: .bottom, spacing: Td.s2) {
                Field(label: "Invité, sans profil", text: $guest, placeholder: "Son prénom", icon: .user)
                    .onSubmit(addGuest)
                TdButton(title: "Ajouter", icon: .plus,
                         state: guest.trimmingCharacters(in: .whitespaces).isEmpty ? .disabled : .normal) { addGuest() }
                    .fixedSize()
            }
            Text("Ou un profil de la cible").font(.td(13, .semibold)).foregroundStyle(Td.ink2).padding(.top, Td.s2)
            ScrollView {
                VStack(spacing: Td.s2) {
                    if let players {
                        let free = players.filter { !taken.contains($0.id) }
                        if free.isEmpty {
                            EmptyState(icon: .users, text: "Tous les profils de la cible sont déjà inscrits.")
                        }
                        ForEach(free) { p in
                            Button { onPick(p) } label: {
                                HStack(spacing: Td.s3) {
                                    Avatar(name: p.nickname,
                                           url: p.photo ? base.appendingPathComponent("api/players/\(p.id)/photo") : nil,
                                           size: 36)
                                    Text(p.nickname).font(.td(17, .semibold)).foregroundStyle(Td.ink)
                                    Spacer()
                                    Icon(name: .plus, size: 20).foregroundStyle(Td.sunset)
                                }
                                .padding(.horizontal, 14)
                                .frame(minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: Td.rMd).fill(Td.verreMoyen))
                            }
                            .buttonStyle(PressScale())
                        }
                    } else {
                        Spinner(size: 28).padding(.top, Td.s8)
                    }
                }
            }
        }
        .padding(.horizontal, Td.s4)
        .task { players = try? await LobbyAPI.players(at: base) }
    }

    private func addGuest() {
        let name = guest.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onGuest(String(name.prefix(20)))
    }
}

/// Tirage au sort : les matchs du premier tour. L'organisateur peut retirer ou lancer.
struct TournamentDrawView: View {
    @EnvironmentObject var app: AppModel
    let base: URL
    let info: TournamentInfo
    var onUpdate: (TournamentInfo?) -> Void
    var onBack: () -> Void

    @State private var busy: String?
    @State private var error: String?

    private var boss: Bool { app.playerId == info.organizer || app.isOwner }

    var body: some View {
        Stage {
            VStack(alignment: .leading, spacing: 10) {
                NavBar(title: "Tirage au sort", back: "Tournoi") {
                    // Revenir aux inscriptions : le tirage sera refait.
                    if boss { send("redo") } else { onBack() }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.rounds.first?.title.replacingOccurrences(of: "8e de", with: "8es de") ?? "")
                        .font(.custom("PermanentMarker-Regular", size: 34))
                        .foregroundStyle(Td.sunset)
                        .shadow(color: Td.sunset.opacity(0.45), radius: 16)
                        .rotationEffect(.degrees(-3))
                    Text(info.summary).font(.td(13)).foregroundStyle(Td.ink2)
                }
                .padding(.horizontal, Td.s1)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array((info.rounds.first?.matches ?? []).enumerated()), id: \.element.id) { i, m in
                            row(i + 1, m)
                        }
                        if let error { Banner(text: error, error: true) }
                    }
                }
                if boss {
                    HStack(spacing: Td.s2) {
                        TdButton(title: "Retirer", variant: .secondary, icon: .refreshCw, block: true,
                                 state: busy == "draw" ? .loading : .normal) { send("draw") }
                        TdButton(title: "Lancer", icon: .play, block: true,
                                 state: busy == "start" ? .loading : .normal) { send("start") }
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1.4)
                    }
                } else {
                    Text("L’organisateur va lancer le tournoi.")
                        .font(.td(13)).foregroundStyle(Td.ink3).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, Td.s2)
            .padding(.bottom, Td.s5)
        }
    }

    private func row(_ n: Int, _ m: TournamentMatch) -> some View {
        let mine = m.a?.id == app.playerId || m.b?.id == app.playerId
        return HStack(spacing: Td.s2) {
            Text("\(n)").font(.tdRounded(13, .heavy)).foregroundStyle(Td.ink3).frame(width: 18, alignment: .leading)
            if let a = m.a {
                Avatar(name: a.name, url: a.photoURL(base: base), size: 26)
                Text(a.name).font(.td(15, mine ? .bold : .semibold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("contre").font(.td(12)).foregroundStyle(Td.ink3)
            if let b = m.b {
                Text(b.name).font(.td(15, mine ? .bold : .semibold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Avatar(name: b.name, url: b.photoURL(base: base), size: 26)
            } else {
                Text("Place libre").font(.td(15)).foregroundStyle(Td.ink3).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Circle().strokeBorder(Td.bordControle, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .frame(width: 26, height: 26)
            }
        }
        .padding(.horizontal, Td.s3)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: Td.rMd).fill(Td.verreLeger))
        .overlay(RoundedRectangle(cornerRadius: Td.rMd).strokeBorder(Td.verreBord))
        .accessibilityElement(children: .combine)
    }

    private func send(_ action: String) {
        busy = action
        error = nil
        Task {
            defer { busy = nil }
            do {
                onUpdate(try await LobbyAPI.tournamentAction(action, at: base, app: app))
                if action == "start" { onBack() }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

extension LobbyAPI {
    enum TournamentError: LocalizedError {
        case exists, notEnough, full, closed, taken, notBoss, other(Int)

        var errorDescription: String? {
            switch self {
            case .exists: "Un tournoi est déjà en cours sur la cible."
            case .notEnough: "Il faut au moins 3 joueurs pour un tournoi."
            case .full: "Le tournoi est complet, 16 joueurs max."
            case .closed: "Le tirage est déjà fait, les inscriptions sont fermées."
            case .taken: "Ce nom est déjà dans le tournoi."
            case .notBoss: "Seul l’organisateur peut faire ça."
            case let .other(s): "Le Pi a répondu \(s)."
            }
        }
    }

    /// POST /api/tournament (créer) ou /api/tournament/<action> : join, add, remove, settings, draw, redo, start, cancel.
    @MainActor
    static func tournamentAction(
        _ action: String?, at base: URL, app: AppModel, _ extra: [String: Any] = [:]
    ) async throws -> TournamentInfo? {
        var url = base.appendingPathComponent("api/tournament")
        if let action { url.appendPathComponent(action) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        app.authorize(&req)
        req.httpBody = try JSONSerialization.data(withJSONObject: extra.merging(["player": app.playerId]) { a, _ in a })
        let data: Data, res: URLResponse
        do {
            (data, res) = try await session.data(for: req)
        } catch {
            throw PiError.unreachable
        }
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        let err = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        switch status {
        case 200: break
        case 401: throw ProfileError.signedOut
        case 403: throw TournamentError.notBoss
        case 410: throw TournamentError.full
        case 409:
            switch err {
            case "en_cours": throw TournamentError.exists
            case "pas_assez": throw TournamentError.notEnough
            case "pris": throw TournamentError.taken
            default: throw TournamentError.closed
            }
        default: throw TournamentError.other(status)
        }
        struct Reply: Decodable { let tournament: TournamentInfo? }
        return try JSONDecoder().decode(Reply.self, from: data).tournament
    }
}
