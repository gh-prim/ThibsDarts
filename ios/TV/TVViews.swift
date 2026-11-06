import SwiftUI

// Écrans Apple TV (planches Connexion, Main, Jeu501, Cricket, TourSuivant, Victoire, Fete180).

/// "64,0" : une décimale, virgule française.
func tvDecimal(_ v: Double) -> String {
    String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
}

/// Grille plein écran des planches : 1920 x 1080, marges 90 et 60.
private let tvPadH: CGFloat = 90
private let tvPadV: CGFloat = 60

// MARK: Connexion

struct TVSearchView: View {
    var body: some View {
        VStack(spacing: Td.s8) {
            TVLogo(height: 96)
            HStack(spacing: Td.s4) {
                Spinner(size: 40)
                Text("On cherche ta cible sur le Wi-Fi.").font(.td(36, .semibold))
            }
            .foregroundStyle(Td.ink2)
        }
    }
}

struct TVConnexionView: View {
    @EnvironmentObject var model: TVModel

    var body: some View {
        VStack(spacing: Td.s8) {
            TVLogo(height: 96)
            if model.found.isEmpty {
                Text("Pas de cible trouvée.").font(.td(56, .bold))
                Text("Allume le Pi et mets l'Apple TV sur le même Wi-Fi.")
                    .font(.td(30)).foregroundStyle(Td.ink2)
            } else {
                Text("Quelle cible on affiche ?").font(.td(56, .bold))
                HStack(spacing: Td.s6) {
                    ForEach(model.found) { pi in
                        Button {
                            model.choose(pi)
                        } label: {
                            HStack(spacing: Td.s4) {
                                Icon(name: .target, size: 40).foregroundStyle(Td.sunset)
                                Text("Cible de \(pi.owner)").font(.td(34, .semibold))
                            }
                            .padding(.horizontal, Td.s8).padding(.vertical, Td.s6)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
            Button {
                Task { await model.search() }
            } label: {
                HStack(spacing: Td.s3) {
                    Icon(name: .refreshCw, size: 30)
                    Text("Chercher encore").font(.td(30, .semibold))
                }
                .padding(.horizontal, Td.s6).padding(.vertical, Td.s4)
            }
            .buttonStyle(.card)
        }
        .padding(80)
    }
}

// MARK: Connecté

struct TVLiveView: View {
    @EnvironmentObject var model: TVModel

    var body: some View {
        ZStack {
            content
            if let up = model.nextUp, let g = model.info?.game, g.winner == nil {
                TVStage { TVNextUpView(up: up, game: g) }.transition(.opacity)
            }
            if model.fete180, let g = model.info?.game {
                TVFete180View(name: g.current).transition(.opacity)
            }
        }
        .task { await model.follow() }
    }

    @ViewBuilder private var content: some View {
        if let info = model.info {
            if let g = info.game, info.isPlaying {
                if g.winner != nil {
                    TVVictoryView(game: g)
                } else if g.kind == "cricket" {
                    TVCricketView(game: g)
                } else {
                    TVGameView(game: g)
                }
            } else if info.isOpen {
                TVSalonView(info: info)
            } else {
                TVIdleView(owner: info.hostName)
            }
        } else {
            TVSearchView()
        }
    }
}

struct TVIdleView: View {
    let owner: String

    var body: some View {
        VStack(spacing: Td.s6) {
            TVLogo(height: 120)
            Text("Prêt à jouer").font(.td(56, .bold))
            Text("\(owner) ouvre un salon depuis l'écran de la cible.")
                .font(.td(30)).foregroundStyle(Td.ink2)
        }
    }
}

// MARK: Salon (planche Main)

struct TVSalonView: View {
    @EnvironmentObject var model: TVModel
    let info: LobbyInfo

    private var joinText: String {
        let host = model.base?.host ?? ""
        let port = model.base?.port ?? 8420
        return "thibsdarts://join?h=\(host)&p=\(port)&c=\(info.code ?? "")"
    }

    var body: some View {
        HStack(spacing: 80) {
            VStack(alignment: .leading, spacing: Td.s8) {
                TVLogo(height: 72)
                VStack(alignment: .leading, spacing: Td.s2) {
                    Text("Salon de \(info.hostName)").font(.td(76, .heavy)).tracking(-1.5)
                    Text(info.label).font(.td(34)).foregroundStyle(Td.ink2)
                }
                HStack(spacing: 40) {
                    TVQRCode(text: joinText, size: 300)
                    VStack(alignment: .leading, spacing: Td.s3) {
                        Text("Scanne avec l'app\nou tape le code").font(.td(28)).foregroundStyle(Td.ink2)
                        if let code = info.code {
                            Text(code).font(.tdRounded(96, .black)).tracking(12)
                        }
                    }
                }
            }
            .frame(width: 760, alignment: .leading)
            VStack(alignment: .leading, spacing: Td.s6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ils sont là").font(.td(34, .bold))
                    Spacer()
                    Text("\(info.players.count) sur 8").font(.td(28)).foregroundStyle(Td.ink2)
                }
                VStack(spacing: Td.s3) {
                    ForEach(info.players) { p in
                        TVPlayerRow(
                            name: p.name,
                            url: model.base.flatMap { LobbyAPI.photoURL(base: $0, player: p) },
                            sub: p.host ? (p.playing == false ? "Hôte, ne joue pas" : "Hôte") : (p.connected ? "Prêt" : "Sur la cible"),
                            ready: p.connected && !p.host
                        )
                    }
                }
                Text("\(info.hostName) lance la partie depuis l'écran de la cible.")
                    .font(.td(28)).foregroundStyle(Td.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, tvPadH).padding(.vertical, tvPadV)
    }
}

// MARK: Partie (planche Jeu501, et les autres modes)

/// En-tête logo + "501 · Manche 2".
struct TVHeader: View {
    let text: String
    var body: some View {
        HStack(spacing: Td.s4) {
            TVLogo(height: 56)
            Text(text).font(.td(28)).foregroundStyle(Td.ink2).lineLimit(1)
        }
    }
}

func tvHeader(_ g: LiveGame) -> String {
    if let t = g.title { return t }
    return "\(g.mode) · Manche \(g.leg)"
}

func tvPlayerSub(_ g: LiveGame, _ p: LivePlayer) -> String? {
    if let d = p.detail { return d }
    var parts: [String] = []
    if let a = p.average { parts.append("Moy. \(tvDecimal(a))") }
    if g.legsToWin > 1 { parts.append("\(p.legs) manche\(p.legs > 1 ? "s" : "")") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

struct TVGameView: View {
    @EnvironmentObject var model: TVModel
    let game: LiveGame

    private var me: LivePlayer? { game.players.first { $0.name == game.current } }

    var body: some View {
        HStack(spacing: 48) {
            VStack(alignment: .leading, spacing: Td.s6) {
                TVHeader(text: tvHeader(game))
                VStack(spacing: Td.s3) {
                    ForEach(game.players, id: \.name) { p in
                        TVPlayerRow(
                            name: p.name,
                            url: model.photoURL(p.name),
                            sub: tvPlayerSub(game, p),
                            score: p.remaining,
                            active: p.name == game.current
                        )
                    }
                }
            }
            .frame(width: 460)
            TVDartboard(darts: game.darts, aimed: game.checkout?.first, heat: heat)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: Td.s8) {
                if game.isX01 {
                    TVScore(
                        value: me?.remaining ?? 0,
                        label: "\(game.current), il reste",
                        sub: game.bust ? "Bust. Score remis à \(me?.remaining ?? 0)." : "Tour en cours : \(game.turnScore)",
                        out: game.checkout != nil,
                        bust: game.bust
                    )
                } else {
                    TVScore(
                        value: game.scoreValue ?? me?.remaining ?? 0,
                        label: game.scoreLabel ?? "Score de \(game.current)",
                        sub: me?.detail ?? "Tour en cours : \(game.turnScore)",
                        size: 220
                    )
                }
                TVDartSlots(darts: game.darts, closed: game.bust)
                if let route = game.checkout, !route.isEmpty, !game.bust {
                    TVCheckout(route: route)
                }
            }
            .frame(width: 500, alignment: .leading)
        }
        .padding(.horizontal, tvPadH).padding(.vertical, tvPadV)
    }

    /// Numéro visé en Clock et Shanghai (le Pi le publie en scoreValue).
    private var heat: Set<Int> {
        guard game.kind == "clock" || game.kind == "shanghai", let v = game.scoreValue, (1...25).contains(v) else { return [] }
        return [v]
    }
}

// MARK: Cricket (planche Cricket)

struct TVCricketView: View {
    let game: LiveGame
    static let numbers = [20, 19, 18, 17, 16, 15, 25]

    private func marks(_ p: LivePlayer, _ row: Int) -> Int {
        guard let m = p.marks, row < m.count else { return 0 }
        return m[row]
    }

    /// Numéros que tout le monde n'a pas encore fermés.
    private var open: Set<Int> {
        Set(Self.numbers.enumerated().filter { row, _ in game.players.contains { marks($0, row) < 3 } }.map(\.element))
    }

    var body: some View {
        HStack(spacing: 64) {
            VStack(alignment: .leading, spacing: Td.s6) {
                TVHeader(text: "\(game.title ?? "Cricket") · \(game.current) au tir")
                board
                    .padding(Td.s5)
                    .background(RoundedRectangle(cornerRadius: 36).fill(Td.verreLeger))
                    .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(Td.verreBord))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: Td.s8) {
                TVDartboard(darts: game.darts, heat: open)
                TVDartSlots(darts: game.darts)
            }
            .frame(width: 640)
        }
        .padding(.horizontal, tvPadH).padding(.vertical, tvPadV)
    }

    private var board: some View {
        VStack(spacing: Td.s2) {
            HStack(spacing: Td.s2) {
                Color.clear.frame(width: 140, height: 1)
                ForEach(game.players, id: \.name) { p in
                    let active = p.name == game.current
                    VStack(spacing: 0) {
                        Text(p.name).font(.td(28, .semibold)).lineLimit(1)
                            .foregroundStyle(active ? Td.fluo : Td.ink2)
                        Text("\(p.remaining)").font(.tdRounded(48, .heavy)).monospacedDigit()
                            .foregroundStyle(active ? Td.ink : Td.ink2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(Self.numbers.enumerated()), id: \.offset) { row, n in
                let closed = !open.contains(n)
                HStack(spacing: Td.s2) {
                    Text(n == 25 ? "Bull" : "\(n)").font(.tdRounded(44, .heavy)).frame(width: 140)
                    ForEach(game.players, id: \.name) { p in
                        TVCricketMark(n: marks(p, row)).frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 84)
                .background(
                    RoundedRectangle(cornerRadius: Td.rLg)
                        .fill(row % 2 == 0 ? Td.verreLeger : .clear)
                )
                .opacity(closed ? 0.35 : 1)
            }
        }
    }
}

// MARK: Joueur suivant (planche TourSuivant)

struct TVNextUpView: View {
    @EnvironmentObject var model: TVModel
    let up: TVModel.NextUp
    let game: LiveGame

    private var me: LivePlayer? { game.players.first { $0.name == up.name } }

    private var line: String? {
        guard let prev = up.previous, let s = up.previousScore else { return nil }
        if game.isX01, let r = up.previousRemaining { return "\(prev) a fait \(s). Il lui reste \(r)." }
        return "\(prev) a fait \(s)."
    }

    var body: some View {
        HStack(spacing: 80) {
            VStack(alignment: .leading, spacing: Td.s8) {
                if let line { Text(line).font(.td(28)).foregroundStyle(Td.ink2) }
                HStack(spacing: 40) {
                    TVAvatar(name: up.name, url: model.photoURL(up.name), size: 180)
                    Text("À \(up.name).").font(.td(140, .heavy)).tracking(-3).lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: Td.s8) {
                if game.isX01 {
                    TVScore(
                        value: me?.remaining ?? 0,
                        label: "Il te reste",
                        sub: me?.average.map { "Moyenne du match : \(tvDecimal($0))" }
                    )
                    if let route = game.checkout, !route.isEmpty { TVCheckout(route: route) }
                } else {
                    TVScore(
                        value: game.scoreValue ?? me?.remaining ?? 0,
                        label: game.youLabel ?? "Ton score",
                        sub: me?.detail,
                        size: 220
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, tvPadH).padding(.vertical, tvPadV)
    }
}

// MARK: 180 (planche Fete180)

struct TVFete180View: View {
    let name: String

    var body: some View {
        ZStack {
            Td.betonNuit.ignoresSafeArea()
            TVHorizon()
            VStack(spacing: Td.s8) {
                TVSprayTag(text: "180", size: 320, pink: true)
                Text("Trois T20. \(name) a même pas transpiré.").font(.td(40, .semibold))
            }
        }
    }
}

/// Lueur golden hour en bas de l'écran (td-fete).
struct TVHorizon: View {
    var body: some View {
        GeometryReader { geo in
            RadialGradient(
                stops: [
                    .init(color: Color(hex: 0xFF7A2F, alpha: 0.30), location: 0),
                    .init(color: Color(hex: 0xFF4D8D, alpha: 0.14), location: 0.45),
                    .init(color: .clear, location: 0.75),
                ],
                center: UnitPoint(x: 0.5, y: 1.18), startRadius: 0, endRadius: geo.size.width * 0.6
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: Victoire (planche Victoire)

struct TVVictoryView: View {
    @EnvironmentObject var model: TVModel
    let game: LiveGame

    private var winners: [String] { (game.winner ?? "").components(separatedBy: " et ") }
    private var isDraw: Bool { winners.count > 1 }
    private var solo: Bool { game.players.count == 1 }

    private var ranking: [LivePlayer] {
        let others = game.players.filter { !winners.contains($0.name) }
        let sorted = game.isX01 ? others.sorted { $0.remaining < $1.remaining } : others
        return game.players.filter { winners.contains($0.name) } + sorted
    }

    private var tag: String { game.endTag ?? (isDraw ? "ÉGALITÉ" : (solo ? "FINI" : "GAGNÉ")) }

    private var copy: String {
        if let c = game.endCopy { return c }
        if isDraw { return "\(game.winner ?? "") à égalité. Revanche ?" }
        return "\(game.winner ?? "") plie la partie. Sans forcer."
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color(hex: 0x0B0B0D)
                TVHorizon()
                VStack(spacing: Td.s8) {
                    TVSprayTag(text: tag, size: tag == "GAGNÉ" ? 220 : 170)
                    Text(copy).font(.td(36, .medium)).multilineTextAlignment(.center)
                    if let stats = game.stats, !stats.isEmpty {
                        HStack(spacing: 64) {
                            ForEach(stats, id: \.label) { s in
                                VStack(spacing: Td.s1) {
                                    Text(s.value).font(.tdRounded(64, .heavy))
                                    Text(s.label).font(.td(26)).foregroundStyle(Td.ink2)
                                }
                            }
                        }
                    }
                }
                .padding(64)
            }
            VStack(alignment: .leading, spacing: Td.s6) {
                Text("Classement").font(.td(34, .bold))
                VStack(spacing: Td.s3) {
                    ForEach(ranking, id: \.name) { p in
                        TVPlayerRow(
                            name: p.name,
                            url: model.photoURL(p.name),
                            sub: tvPlayerSub(game, p),
                            score: p.remaining,
                            winner: winners.contains(p.name)
                        )
                    }
                }
                Text("Stats envoyées sur l'iPhone de chacun.").font(.td(22)).foregroundStyle(Td.ink3)
            }
            .padding(.leading, 48).padding(.trailing, tvPadH).padding(.vertical, tvPadV)
            .frame(width: 640)
            .frame(maxHeight: .infinity)
            .background(Color(hex: 0x121214))
            .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1) }
        }
        .ignoresSafeArea()
    }
}
