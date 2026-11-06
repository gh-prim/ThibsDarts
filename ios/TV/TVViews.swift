import SwiftUI

// Écrans Apple TV (planches Connexion, Salon, Jeu501, TourSuivant, Victoire, Fete180).

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
            if let up = model.nextUp, model.info?.game?.winner == nil {
                TVNextUpView(up: up).transition(.opacity)
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

// MARK: Salon

struct TVSalonView: View {
    @EnvironmentObject var model: TVModel
    let info: LobbyInfo

    private var joinText: String {
        let host = model.base?.host ?? ""
        let port = model.base?.port ?? 8420
        return "thibsdarts://join?h=\(host)&p=\(port)&c=\(info.code ?? "")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Td.s8) {
            HStack {
                TVLogo(height: 64)
                Spacer()
                Text(info.label).font(.td(30, .semibold)).foregroundStyle(Td.ink2)
            }
            HStack(alignment: .top, spacing: 96) {
                VStack(alignment: .leading, spacing: Td.s6) {
                    Text("Salon de \(info.hostName)").font(.td(64, .bold))
                    Text("Scanne avec l'appli ThibsDarts pour rejoindre.")
                        .font(.td(30)).foregroundStyle(Td.ink2)
                    TVQRCode(text: joinText, size: 340)
                    if let code = info.code {
                        HStack(alignment: .firstTextBaseline, spacing: Td.s4) {
                            Text("Code").font(.td(30, .semibold)).foregroundStyle(Td.ink2)
                            Text(code).font(.tdRounded(96, .black)).tracking(12)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Td.s4) {
                    Text("Ils sont là, \(info.players.count) sur 8").font(.td(36, .bold))
                    ScrollView {
                        VStack(spacing: Td.s3) {
                            ForEach(info.players) { p in
                                TVPlayerRow(
                                    name: p.name,
                                    url: model.base.flatMap { LobbyAPI.photoURL(base: $0, player: p) },
                                    sub: p.host ? "Hôte" : (p.connected ? "Prêt" : "Sur la cible"),
                                    ready: p.connected && !p.host
                                )
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Text("\(info.hostName) lance la partie depuis l'écran de la cible.")
                        .font(.td(28)).foregroundStyle(Td.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 96).padding(.vertical, 64)
    }
}

// MARK: Partie

struct TVGameView: View {
    @EnvironmentObject var model: TVModel
    let game: LiveGame

    private var title: String {
        let name = game.title ?? game.mode
        return game.legsToWin > 1 ? "\(name) · Manche \(game.leg)" : name
    }

    private var me: LivePlayer? { game.players.first { $0.name == game.current } }

    var body: some View {
        VStack(alignment: .leading, spacing: Td.s6) {
            HStack {
                TVLogo(height: 56)
                Spacer()
                Text(title).font(.td(30, .semibold)).foregroundStyle(Td.ink2)
            }
            HStack(alignment: .top, spacing: Td.s8) {
                players.frame(width: 460)
                center.frame(maxWidth: .infinity)
                right.frame(width: 500)
            }
        }
        .padding(.horizontal, 64).padding(.vertical, 48)
    }

    private var players: some View {
        VStack(spacing: Td.s3) {
            ForEach(game.players, id: \.name) { p in
                TVPlayerRow(
                    name: p.name,
                    url: model.photoURL(p.name),
                    sub: sub(p),
                    score: p.remaining,
                    active: p.name == game.current
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func sub(_ p: LivePlayer) -> String? {
        if let d = p.detail { return d }
        var parts: [String] = []
        if let a = p.average { parts.append(String(format: "Moy. %.1f", a).replacingOccurrences(of: ".", with: ",")) }
        if game.legsToWin > 1 { parts.append("\(p.legs) manche\(p.legs > 1 ? "s" : "")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var center: some View {
        if game.kind == "cricket" {
            TVCricketTable(game: game)
        } else {
            TVDartboard(darts: game.darts, aimed: game.checkout?.first, heat: heat)
                .frame(maxHeight: 820)
        }
    }

    /// Numéro visé en Clock et Shanghai (le Pi le publie en scoreValue).
    private var heat: Set<Int> {
        guard game.kind == "clock" || game.kind == "shanghai", let v = game.scoreValue, (1...25).contains(v) else { return [] }
        return [v]
    }

    private var right: some View {
        VStack(alignment: .leading, spacing: Td.s6) {
            Text(game.current).font(.td(44, .bold)).lineLimit(1)
            if game.isX01 {
                TVScore(
                    value: me?.remaining ?? 0,
                    label: "Il reste",
                    sub: game.bust ? "Bust. Score remis à \(me?.remaining ?? 0)." : "Ce tour : \(game.turnScore)",
                    out: game.checkout != nil,
                    bust: game.bust
                )
            } else {
                TVScore(
                    value: game.scoreValue ?? me?.remaining ?? 0,
                    label: game.scoreLabel ?? "Score",
                    sub: me?.detail ?? "Ce tour : \(game.turnScore)",
                    size: 200
                )
            }
            TVDartSlots(darts: game.darts, closed: game.bust)
            if let route = game.checkout, !route.isEmpty, !game.bust {
                TVCheckout(route: route)
            }
            Spacer(minLength: 0)
            Text("Ensuite : \(game.next)").font(.td(28)).foregroundStyle(Td.ink2)
        }
    }
}

/// Tableau Cricket : une colonne par joueur, une ligne par numéro.
struct TVCricketTable: View {
    let game: LiveGame
    private let numbers = ["20", "19", "18", "17", "16", "15", "Bull"]

    var body: some View {
        VStack(spacing: Td.s2) {
            HStack(spacing: Td.s2) {
                Color.clear.frame(width: 120, height: 1)
                ForEach(game.players, id: \.name) { p in
                    Text(p.name).font(.td(26, .semibold)).lineLimit(1)
                        .foregroundStyle(p.name == game.current ? Td.fluo : Td.ink2)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(numbers.enumerated()), id: \.offset) { row, n in
                HStack(spacing: Td.s2) {
                    Text(n).font(.tdRounded(44, .heavy)).frame(width: 120)
                    ForEach(game.players, id: \.name) { p in
                        TVCricketMark(n: p.marks.flatMap { row < $0.count ? $0[row] : nil } ?? 0)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 88)
                .background(RoundedRectangle(cornerRadius: Td.rLg).fill(row % 2 == 0 ? Td.verreLeger : .clear))
            }
        }
    }
}

// MARK: Moments forts

struct TVNextUpView: View {
    @EnvironmentObject var model: TVModel
    let up: TVModel.NextUp

    var body: some View {
        ZStack {
            Td.betonNuit.opacity(0.92).ignoresSafeArea()
            VStack(spacing: Td.s6) {
                TVAvatar(name: up.name, url: model.photoURL(up.name), size: 180)
                    .overlay(Circle().strokeBorder(Td.fluo, lineWidth: 4))
                    .shadow(color: Td.fluo.opacity(0.4), radius: 30)
                Text("À \(up.name).").font(.td(120, .black))
                if let prev = up.previous, let s = up.previousScore {
                    let rest = up.previousRemaining.map { " Il reste \($0)." } ?? ""
                    let line = model.info?.game?.isX01 == true ? "\(prev) a fait \(s).\(rest)" : "\(prev) a fait \(s)."
                    Text(line).font(.td(36)).foregroundStyle(Td.ink2)
                }
            }
        }
    }
}

struct TVFete180View: View {
    let name: String

    var body: some View {
        ZStack {
            Td.betonNuit.ignoresSafeArea()
            EllipticalGradient(
                stops: [
                    .init(color: Td.sunset.opacity(0.30), location: 0),
                    .init(color: Td.crepuscule.opacity(0.14), location: 0.45),
                    .init(color: .clear, location: 0.75),
                ],
                center: UnitPoint(x: 0.5, y: 1.18)
            )
            .ignoresSafeArea()
            VStack(spacing: Td.s8) {
                TVSprayTag(text: "180", size: 320, pink: true)
                Text("Trois T20. \(name) a même pas transpiré.").font(.td(40, .semibold))
            }
        }
    }
}

// MARK: Victoire

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

    private var tag: String { isDraw ? "ÉGALITÉ" : (solo ? "FINI" : "GAGNÉ") }

    private var copy: String {
        if isDraw { return "\(game.winner ?? "") à égalité. Revanche ?" }
        if solo { return "\(game.winner ?? "") termine avec \(game.players[0].remaining)." }
        return "\(game.winner ?? "") plie la partie. Sans forcer."
    }

    var body: some View {
        HStack(spacing: 64) {
            VStack(spacing: Td.s8) {
                TVSprayTag(text: tag, size: isDraw ? 150 : 200)
                Text(copy).font(.td(40, .semibold)).multilineTextAlignment(.center)
                Text("\(model.info?.hostName ?? "L'hôte") relance depuis l'écran de la cible.")
                    .font(.td(28)).foregroundStyle(Td.ink2)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: Td.s4) {
                Text("Classement").font(.td(36, .bold))
                ForEach(Array(ranking.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: Td.s4) {
                        Text("\(i + 1)").font(.tdRounded(40, .heavy)).foregroundStyle(Td.ink2).frame(width: 48)
                        TVPlayerRow(
                            name: p.name,
                            url: model.photoURL(p.name),
                            sub: p.detail,
                            score: p.remaining,
                            winner: winners.contains(p.name)
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Td.s8)
            .frame(width: 640)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Td.rXl).fill(Td.verreLeger))
            .overlay(RoundedRectangle(cornerRadius: Td.rXl).strokeBorder(Td.verreBord))
        }
        .padding(64)
    }
}
