import SwiftUI

/// Accueil avec les onglets (planche "2. Jouer").
struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @StateObject private var history = HistoryModel()
    @State private var tab = "jouer"

    private let tabs = [
        TabBar.Item(id: "jouer", icon: .target, label: "Jouer"),
        TabBar.Item(id: "stats", icon: .chartLine, label: "Stats"),
        TabBar.Item(id: "historique", icon: .history, label: "Historique"),
        TabBar.Item(id: "profil", icon: .user, label: "Profil"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case "jouer": PlayTab()
            case "profil": ProfileView(title: "Profil", onBack: nil, onDone: { tab = "jouer" })
            case "stats": StatsTab()
            default: HistoryTab()
            }
            TabBar(items: tabs, value: $tab)
                .padding(.horizontal, Td.s4)
                .padding(.bottom, Td.s2)
                .opacity(tab == "profil" ? 0 : 1)
        }
        .environmentObject(history)
        .fullScreenCover(item: $app.lobby) { _ in SalonView().environmentObject(app) }
        // Recharge l'historique en changeant d'onglet et en sortant d'une partie.
        .task(id: "\(tab)-\(app.lobby == nil)-\(app.piBase?.absoluteString ?? "")") { await history.load(app: app) }
    }
}

/// Onglet Jouer : le salon ouvert sur le Pi, Créer, Code, dernière partie.
private struct PlayTab: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var history: HistoryModel
    @State private var lastDetail: HistoryMatch?
    @State private var info: LobbyInfo?
    @State private var joining = false
    @State private var error: String?
    @State private var showJoin = false
    @State private var showCreate = false
    @State private var created: (LobbyInfo, URL)?

    var body: some View {
        Stage {
            ScrollView {
                VStack(alignment: .leading, spacing: Td.s4) {
                    Text("Salut \(app.nickname).")
                        .font(.td(34, .heavy))
                        .tracking(-0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Td.s3)
                        .padding(.bottom, Td.s2)
                    salonCard
                    HStack(spacing: Td.s2) {
                        TdButton(title: "Créer", variant: .secondary, icon: .plus, block: true) { create() }
                        TdButton(title: "Code", variant: .secondary, icon: .search, block: true) { showJoin = true }
                    }
                    if let error { Banner(text: error, error: true) }
                    Text("Ta dernière partie").font(.td(13, .semibold)).foregroundStyle(Td.ink2).padding(.top, Td.s2)
                    if let last = history.matches.first {
                        MatchHistoryList(matches: [last], me: app.playerId) { lastDetail = $0 }
                    } else {
                        EmptyState(icon: .history, text: "Aucune partie. Le minimum, c’est d’en lancer une.")
                    }
                }
                .padding(.horizontal, Td.s4)
                .padding(.top, Td.s4)
                .padding(.bottom, 120)
            }
        }
        .task(id: app.piBase) { await poll() }
        .sheet(item: $lastDetail) { m in
            MatchDetailView(match: m).environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationBackground(Td.beton)
        }
        .fullScreenCover(isPresented: $showJoin) { JoinView(onBack: { showJoin = false }).environmentObject(app) }
        .fullScreenCover(isPresented: $showCreate, onDismiss: {
            // Le salon créé s'affiche une fois Nouvelle partie fermé.
            if let c = created {
                created = nil
                app.enter(lobby: c.0, base: c.1)
            }
        }) {
            NewGameView(onBack: { showCreate = false }) { info, base in
                created = (info, base)
                showCreate = false
            }
            .environmentObject(app)
        }
    }

    /// Pas de nouvelle partie si une partie tourne ou si un salon est déjà ouvert.
    private func create() {
        if info?.isPlaying == true {
            error = "Une partie est déjà en cours sur la cible."
        } else if info?.isOpen == true {
            error = "Un salon est déjà ouvert. Rejoins-le juste au-dessus."
        } else {
            error = nil
            showCreate = true
        }
    }

    @ViewBuilder private var salonCard: some View {
        if let info, info.isOpen || info.isPlaying {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if info.isPlaying {
                        Badge(text: "Partie en cours", tone: .sunset, icon: .target)
                    } else {
                        Badge(text: "Salon ouvert", tone: .succes, icon: .check)
                    }
                    Spacer()
                    Text("sur l’écran du Pi").font(.td(13)).foregroundStyle(Td.ink2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Salon de \(info.hostName)").font(.td(22, .bold))
                    Text(info.label.replacingOccurrences(of: " gagnantes", with: "")).font(.td(15)).foregroundStyle(Td.ink2)
                }
                HStack(spacing: Td.s2) {
                    HStack(spacing: Td.s1) {
                        ForEach(info.players.prefix(4)) { p in
                            Avatar(name: p.name, url: app.piBase.flatMap { LobbyAPI.photoURL(base: $0, player: p) }, size: 32)
                        }
                    }
                    Text(inside(info)).font(.td(13)).foregroundStyle(Td.ink2).lineLimit(2)
                }
                if info.isOpen {
                    TdButton(title: "Rejoindre", icon: .arrowRight, block: true, state: joining ? .loading : .normal) {
                        join(info)
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: Td.rXl).fill(Td.sunset.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Td.rXl).strokeBorder(Td.sunset.opacity(0.5)))
            .shadow(color: Td.sunset.opacity(0.25), radius: 16)
        } else {
            VStack(alignment: .leading, spacing: Td.s2) {
                Badge(text: app.piBase == nil ? "Aucun ThibsDarts" : "Pas de salon", icon: .target)
                Text(app.piBase == nil
                     ? "Scanne le QR code d’un salon pour relier ton iPhone à la cible."
                     : "Lance une partie sur l’écran du Pi, elle apparaît ici.")
                    .font(.td(15))
                    .foregroundStyle(Td.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: Td.rXl).fill(Td.verreLeger))
            .overlay(RoundedRectangle(cornerRadius: Td.rXl).strokeBorder(Td.verreBord))
        }
    }

    private func inside(_ info: LobbyInfo) -> String {
        let names = info.players.map(\.name)
        switch names.count {
        case 0: return "Personne pour l’instant"
        case 1: return "\(names[0]) est déjà dedans"
        case 2: return "\(names[0]) et \(names[1]) sont déjà dedans"
        default: return "\(names[0]), \(names[1]) et \(names.count - 2) autres sont déjà dedans"
        }
    }

    private func join(_ info: LobbyInfo) {
        guard let base = app.piBase, let code = info.code else { return }
        joining = true
        error = nil
        Task {
            defer { joining = false }
            do {
                let joined = try await LobbyAPI.join(at: base, code: code, app: app)
                app.enter(lobby: joined, base: base)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            if let base = app.piBase {
                info = try? await LobbyAPI.lobby(at: base)
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

/// Rejoindre un salon : scan du QR ou code à 4 caractères (planche "2. Rejoindre un salon").
struct JoinView: View {
    let onBack: () -> Void

    @EnvironmentObject var app: AppModel
    @StateObject private var camera = Camera()
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Td.betonNuit.ignoresSafeArea()
            VStack(spacing: Td.s4) {
                NavBar(title: "Rejoindre", back: "Jouer", onBack: onBack)
                ZStack {
                    if Camera.hasCamera && camera.available {
                        CameraPreview(session: camera.session)
                    } else {
                        Td.plateauNoir
                        VStack {
                            Text("Caméra indisponible ici").font(.td(13)).foregroundStyle(Td.ink3).padding(.top, Td.s4)
                            Spacer()
                        }
                    }
                    ScanCorners()
                    VStack {
                        Spacer()
                        if busy {
                            Badge(text: "On rejoint le salon...", tone: .info, icon: .loaderCircle)
                        } else {
                            Text("Vise le QR code sur l’écran du Pi").font(.td(15, .semibold))
                        }
                    }
                    .padding(.bottom, Td.s4)
                }
                .frame(height: 380)
                .clipShape(RoundedRectangle(cornerRadius: Td.rXl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Td.rXl, style: .continuous)
                        .strokeBorder(Td.verreBord, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )

                HStack(spacing: Td.s3) {
                    Td.bord.frame(height: 1)
                    Text("ou").font(.td(13)).foregroundStyle(Td.ink3)
                    Td.bord.frame(height: 1)
                }
                Field(
                    label: "Code du salon", text: $code, placeholder: "K7Q2",
                    hint: "4 caractères, affichés sous le QR code.", icon: .search,
                    state: error == nil ? .normal : .error
                )
                .textInputAutocapitalization(.characters)
                .onChange(of: code) { _, v in code = String(v.uppercased().prefix(4)) }
                if let error { Banner(text: error, error: true) }
                Spacer(minLength: 0)
                TdButton(
                    title: "Rejoindre", icon: .arrowRight, block: true,
                    state: busy ? .loading : code.count == 4 ? .normal : .disabled
                ) { join(JoinLink(code: code)) }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
            .padding(.bottom, Td.s2)
            .foregroundStyle(Td.ink)
        }
        .onAppear {
            camera.startScanning { text in
                if let url = URL(string: text), let link = JoinLink(url: url) { join(link) }
            }
        }
        .onDisappear { camera.stop() }
    }

    private func join(_ link: JoinLink) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let base = try await locate(link)
                let info = try await LobbyAPI.join(at: base, code: link.code, app: app)
                camera.stop()
                app.enter(lobby: info, base: base)
                onBack()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Adresse du QR, sinon le Pi connu, sinon Bonjour et le Mac en simulateur.
    private func locate(_ link: JoinLink) async throws -> URL {
        if let h = link.host, let url = URL(string: "http://\(h):\(link.port)") { return url }
        if let known = app.piBase, (try? await LobbyAPI.lobby(at: known)) != nil { return known }
        return try await PiClient().locate(preferred: nil, port: link.port)
    }
}

/// Dans le salon (planche "2. Dans le salon").
struct SalonView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let info = app.lobby?.info
        if let info, info.isPlaying, let game = info.game {
            LiveGameView(info: info, game: game, onLeave: leave)
                .task { await poll() }
        } else {
            waiting(info)
                .task { await poll() }
        }
    }

    private func waiting(_ info: LobbyInfo?) -> some View {
        Stage {
            VStack(alignment: .leading, spacing: Td.s4) {
                NavBar(title: "Salon de \(info?.hostName ?? "")", back: "Quitter") { leave() }
                if let info {
                    VStack(alignment: .leading, spacing: Td.s1) {
                        Text(info.isPlaying ? "C’est parti." : "T’es dedans.").font(.td(28, .heavy)).tracking(-0.3)
                        Text(info.label).font(.td(15)).foregroundStyle(Td.ink2)
                    }
                    Text("Ordre de passage").font(.td(13, .semibold)).foregroundStyle(Td.ink2)
                    ScrollView {
                        VStack(spacing: Td.s2) {
                            ForEach(info.players) { p in
                                PlayerCardView(
                                    name: p.id == info.you ? "\(p.name) (toi)" : p.name,
                                    image: p.id == info.you ? app.photo : nil,
                                    url: app.lobby.flatMap { LobbyAPI.photoURL(base: $0.base, player: p) },
                                    message: p.host ? (p.playing == false ? "Hôte, ne joue pas" : "Hôte") : p.guest ? "Invité" : "Prêt",
                                    ready: !p.host && !p.guest
                                )
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    Toast(title: "Range ton téléphone.", detail: before(info))
                    if !info.isPlaying {
                        HStack(spacing: Td.s1) {
                            Spinner(size: 12)
                            Text("\(info.hostName) lance la partie depuis le Pi").font(.td(12, .semibold))
                        }
                        .padding(.horizontal, Td.s2)
                        .frame(height: 22)
                        .foregroundStyle(Td.ink2)
                        .background(RoundedRectangle(cornerRadius: Td.rXs).fill(Td.verreMoyen))
                    }
                }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
            .padding(.bottom, Td.s2)
        }
    }

    private func before(_ info: LobbyInfo) -> String {
        guard let i = info.players.firstIndex(where: { $0.id == info.you }) else {
            return "On te prévient quand c’est ton tour."
        }
        if i == 0 { return "On te prévient quand c’est ton tour. Tu ouvres le bal." }
        return "On te prévient quand c’est ton tour. \(info.players[i - 1].name) joue juste avant toi."
    }

    private func leave() {
        guard let l = app.lobby else { return }
        let id = l.info.you ?? app.deviceId
        Task { await LobbyAPI.leave(at: l.base, id: id) }
        app.lobby = nil
    }

    private func poll() async {
        var misses = 0
        while !Task.isCancelled, let l = app.lobby {
            // Pendant la partie on suit de près.
            try? await Task.sleep(for: .seconds(l.info.isPlaying ? 1 : 2))
            do {
                var fresh = try await LobbyAPI.lobby(at: l.base)
                fresh.you = l.info.you
                if fresh.state == "closed" || !fresh.players.contains(where: { $0.id == l.info.you }) {
                    // Salon fermé sur le Pi, ou on nous a retiré.
                    app.lobby = nil
                    return
                }
                app.lobby?.info = fresh
                misses = 0
            } catch {
                // Le Pi ne répond plus depuis 30 s : on sort du salon.
                misses += 1
                if misses >= 15 {
                    app.lobby = nil
                    return
                }
            }
        }
    }
}
