import SwiftUI

/// Score en gros chiffres arrondis (ScoreDisplay, tailles m et l).
struct ScoreDisplayView: View {
    let value: Int
    var label: String?
    var sub: String?
    var large = false
    var center = false
    var bust = false

    var body: some View {
        VStack(alignment: center ? .center : .leading, spacing: Td.s1) {
            if let label { Text(label).font(.td(13, .semibold)).foregroundStyle(Td.ink2) }
            Text("\(value)")
                .font(.tdRounded(large ? 140 : 88, .black))
                .tracking(large ? -4 : -2)
                .monospacedDigit()
                .foregroundStyle(bust ? Td.erreur : Td.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            if let sub {
                Text(sub).font(.td(15, bust ? .semibold : .regular)).foregroundStyle(bust ? Td.erreur : Td.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Trois emplacements de fléchettes (DartSlots).
struct DartSlotsView: View {
    let darts: [LiveDart]
    var closed = false

    var body: some View {
        HStack(spacing: Td.s2) {
            ForEach(0..<3, id: \.self) { i in slot(i) }
        }
    }

    @ViewBuilder private func slot(_ i: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Td.rMd)
        Group {
            if i < darts.count {
                let d = darts[i]
                VStack(spacing: 0) {
                    Text(d.label)
                        .font(.tdRounded(24, .black))
                        .foregroundStyle(d.value == 0 ? Td.erreur : Td.ink)
                    Text("\(d.value)").font(.td(12, .medium)).foregroundStyle(Td.ink2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(Td.verreLeger))
                .overlay(shape.strokeBorder(Td.verreBord))
            } else if i == darts.count && !closed {
                Icon(name: .crosshair, size: 24)
                    .foregroundStyle(Td.fluo)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(shape.strokeBorder(Td.fluo, lineWidth: 2))
                    .shadow(color: Td.fluo.opacity(0.4), radius: 10)
            } else {
                Text("\(i + 1)")
                    .font(.tdRounded(24, .black))
                    .foregroundStyle(Td.ink3.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(shape.strokeBorder(Td.bordControle, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
        .frame(height: 64)
    }
}

/// Sortie conseillée (CheckoutHint).
struct CheckoutHintView: View {
    let route: [String]
    var label = "Sortie"

    var body: some View {
        HStack(spacing: Td.s3) {
            Text(label).font(.td(13, .semibold)).foregroundStyle(Td.ink2)
            Spacer()
            ForEach(Array(route.enumerated()), id: \.offset) { i, d in
                let out = i == route.count - 1
                Text(d)
                    .font(.tdRounded(22, .heavy))
                    .monospacedDigit()
                    .foregroundStyle(out ? Td.onAccent : Td.ink)
                    .padding(.horizontal, Td.s2)
                    .frame(minWidth: 56, minHeight: 40)
                    .background {
                        if out {
                            RoundedRectangle(cornerRadius: Td.rSm).fill(Td.goldenHour)
                        } else {
                            RoundedRectangle(cornerRadius: Td.rSm).fill(Td.verreMoyen)
                        }
                    }
            }
        }
        .padding(.vertical, Td.s2)
        .padding(.horizontal, Td.s3)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: Td.rMd).fill(Td.verreLeger))
        .overlay(RoundedRectangle(cornerRadius: Td.rMd).strokeBorder(Td.verreBord))
    }
}

/// Carte de classement : avatar, nom, "Au tir" ou "moy.", score restant.
struct LiveRow: View {
    let name: String
    var image: UIImage?
    var url: URL?
    let remaining: Int
    let average: Double?
    let active: Bool

    var body: some View {
        HStack(spacing: Td.s3) {
            Avatar(name: name, image: image, url: url)
                .overlay(Circle().strokeBorder(active ? Td.fluo : .clear, lineWidth: 2))
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.td(17, .semibold)).lineLimit(1)
                Text(sub).font(.td(13)).foregroundStyle(Td.ink2).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(remaining)")
                .font(.tdRounded(32, .heavy))
                .monospacedDigit()
                .foregroundStyle(active ? Td.ink : Td.ink2)
        }
        .padding(Td.s3)
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(active ? Td.verreMoyen : Td.verreLeger))
        .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(active ? Td.fluo : Td.verreBord))
        .shadow(color: active ? Td.fluo.opacity(0.4) : .clear, radius: 10)
    }

    private var sub: String {
        let avg = average.map { String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") }
        if active { return avg.map { "Au tir · \($0)" } ?? "Au tir" }
        return avg.map { "moy. \($0)" } ?? "En attente"
    }
}

/// Partie en direct (planches "Suivre la partie", "À toi" et la fin).
struct LiveGameView: View {
    let info: LobbyInfo
    let game: LiveGame
    let onLeave: () -> Void

    @EnvironmentObject var app: AppModel
    @State private var dismissedTurn: String?

    private var me: String? { info.players.first { $0.id == info.you }?.name }
    private var title: String {
        "\(game.mode) · Manche \(game.leg)"
    }
    private var turnKey: String { "\(game.leg)-\(game.current)-\(game.players.map(\.remaining))" }

    var body: some View {
        Stage {
            VStack(spacing: 14) {
                NavBar(title: title, back: "Jouer", onBack: onLeave, status: "En direct du Pi")
                if let w = game.winner {
                    winner(w)
                } else if game.current == me && dismissedTurn != turnKey && game.darts.isEmpty {
                    yourTurn
                } else {
                    follow
                }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
            .padding(.bottom, Td.s2)
        }
        .animation(Td.sortie, value: game)
    }

    private func player(_ name: String) -> LivePlayer? { game.players.first { $0.name == name } }

    private func photo(for name: String) -> (UIImage?, URL?) {
        guard let p = info.players.first(where: { $0.name == name }) else { return (nil, nil) }
        if p.id == info.you { return (app.photo, nil) }
        return (nil, app.lobby.flatMap { LobbyAPI.photoURL(base: $0.base, player: p) })
    }

    // MARK: Suivi

    private var follow: some View {
        let cur = player(game.current)
        let closed = game.darts.count == 3 || game.bust
        return VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: Td.s3) {
                ScoreDisplayView(
                    value: cur?.remaining ?? 0,
                    label: game.current == me ? "Tu es au tir, il te reste" : "\(game.current) au tir, il lui reste",
                    sub: game.bust ? "Bust, le score revient." : "Tour en cours: \(game.turnScore)",
                    bust: game.bust
                )
                DartSlotsView(darts: game.darts, closed: closed)
            }
            .padding(Td.s4)
            .background(RoundedRectangle(cornerRadius: Td.rXl).fill(Td.verreLeger))
            .overlay(RoundedRectangle(cornerRadius: Td.rXl).strokeBorder(Td.verreBord))

            Text("Classement").font(.td(13, .semibold)).foregroundStyle(Td.ink2)
            ScrollView {
                VStack(spacing: Td.s2) {
                    ForEach(game.players, id: \.name) { p in
                        let ph = photo(for: p.name)
                        LiveRow(
                            name: p.name == me ? "\(p.name) (toi)" : p.name,
                            image: ph.0, url: ph.1,
                            remaining: p.remaining, average: p.average,
                            active: p.name == game.current
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            if game.next == me && game.current != me {
                Toast(title: "Tu joues juste après.", detail: "Prépare tes fléchettes, on te fait signe.")
            }
        }
    }

    // MARK: À toi

    private var yourTurn: some View {
        let mine = player(game.current)
        let leader = game.players.filter { $0.name != me }.min { $0.remaining < $1.remaining }
        let ph = photo(for: game.current)
        return VStack(spacing: Td.s4) {
            Spacer(minLength: 0)
            Avatar(name: game.current, image: ph.0, url: ph.1, size: 88)
            Text("À toi, \(game.current).").font(.td(34, .heavy)).tracking(-0.5)
            ScoreDisplayView(value: mine?.remaining ?? 0, label: "Il te reste", large: true, center: true)
            if let route = game.checkout, !route.isEmpty {
                CheckoutHintView(route: route)
            }
            if let leader, let mine, leader.remaining < mine.remaining {
                Text("\(leader.name) mène avec \(leader.remaining). Faut y aller.")
                    .font(.td(15)).foregroundStyle(Td.ink2)
            }
            Spacer(minLength: 0)
            TdButton(title: "J’arrive à la cible", icon: .target, block: true) { dismissedTurn = turnKey }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: Fin

    private func winner(_ name: String) -> some View {
        let ph = photo(for: name)
        return VStack(spacing: Td.s4) {
            Spacer(minLength: 0)
            ProfileRing(image: ph.0, size: 120)
                .overlay {
                    if ph.0 == nil, let url = ph.1 {
                        Avatar(name: name, url: url, size: 120)
                    }
                }
            Text(name == me ? "T’as gagné." : "\(name) a gagné.").font(.td(34, .heavy)).tracking(-0.5)
            Text("Regarde l’écran du Pi pour la suite.").font(.td(15)).foregroundStyle(Td.ink2)
            Spacer(minLength: 0)
            TdButton(title: "Retour", variant: .secondary, block: true, action: onLeave)
        }
        .multilineTextAlignment(.center)
    }
}
