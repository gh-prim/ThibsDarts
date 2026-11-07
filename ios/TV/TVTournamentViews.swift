import SwiftUI

// Tournoi sur le projecteur (planches Tournoi, tableau et Tournoi, annonce du match).

extension TournamentInfo {
    /// Match de la cible en ce moment ou prochain match à jouer.
    var focus: TournamentMatch? {
        let all = rounds.flatMap(\.matches)
        return all.first { $0.state == "direct" } ?? all.first { $0.id == next }
    }

    func round(of m: TournamentMatch) -> TournamentRound? {
        rounds.first { $0.matches.contains { $0.id == m.id } }
    }

    /// "A battu Hugo 3 à 1", "Qualifié d'office".
    func lastWin(_ id: String) -> String? {
        guard let m = rounds.flatMap(\.matches).last(where: { $0.winner == id }) else { return nil }
        if m.state == "gratuit" { return "Qualifié d’office" }
        let mine = m.a?.id == id
        guard let other = mine ? m.b : m.a else { return nil }
        let (w, l) = mine ? (m.scoreA, m.scoreB) : (m.scoreB, m.scoreA)
        return "A battu \(other.name) \(w) à \(l)"
    }

    /// "Le gagnant retrouve Inès ou Lucas en finale."
    func after(_ m: TournamentMatch) -> String? {
        guard let r = rounds.firstIndex(where: { $0.matches.contains { $0.id == m.id } }),
              let i = rounds[r].matches.firstIndex(where: { $0.id == m.id }) else { return nil }
        if r + 1 >= rounds.count { return "Le gagnant remporte le tournoi." }
        let up = rounds[r + 1]
        let where_ = up.matches.count == 1 ? "en finale" : "en \(up.title.lowercased())"
        let sibling = rounds[r].matches[i ^ 1]
        if let w = sibling.winner, let p = [sibling.a, sibling.b].compactMap({ $0 }).first(where: { $0.id == w }) {
            return "Le gagnant retrouve \(p.name) \(where_)."
        }
        if let a = sibling.a, let b = sibling.b { return "Le gagnant retrouve \(a.name) ou \(b.name) \(where_)." }
        return nil
    }

    /// "Quarts de finale" pour le badge du tableau.
    var stage: String {
        if let c = champion { return "Vainqueur : \(c.name)" }
        guard let m = focus, let r = round(of: m) else { return "Tirage au sort" }
        return switch r.name {
        case "8es": "8es de finale"
        case "Quarts": "Quarts de finale"
        case "Demies": "Demi-finales"
        default: "Finale"
        }
    }
}

/// Tableau complet : moitié gauche, finale au centre, moitié droite en miroir.
struct TVTournamentView: View {
    @EnvironmentObject var model: TVModel
    let info: TournamentInfo

    private let areaW: CGFloat = 1740
    private let areaH: CGFloat = 820
    private let cardH: CGFloat = 104
    private let gap: CGFloat = 20

    var body: some View {
        ZStack(alignment: .topLeading) {
            header.padding(.horizontal, 90).padding(.top, 56)
            bracket.frame(width: areaW, height: areaH, alignment: .topLeading).offset(x: 90, y: 200)
        }
        .frame(width: 1920, height: 1080, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: Td.s6) {
            TVLogo(height: 64)
            VStack(alignment: .leading, spacing: Td.s1) {
                Text(info.name).font(.td(56, .heavy)).tracking(-1).lineLimit(1)
                Text(info.summary).font(.td(26)).foregroundStyle(Td.ink2)
            }
            Spacer()
            Text(info.stage)
                .font(.td(26, .semibold))
                .foregroundStyle(Td.sunset)
                .padding(.horizontal, Td.s5).padding(.vertical, Td.s2)
                .background(Capsule().fill(Td.sunsetFond))
        }
    }

    // MARK: Placement

    private struct Slot {
        let match: TournamentMatch
        let frame: CGRect
        /// Côté droit : les traits partent vers la gauche.
        let right: Bool
    }

    /// Colonnes : tours de la moitié gauche, finale, tours de la moitié droite.
    private var layout: (slots: [Slot], columns: [(String, CGRect)]) {
        let side = max(info.rounds.count - 1, 0)
        let finalW: CGFloat = 280
        let colW: CGFloat = side >= 3 ? 230 : 260
        // Les demies sont un peu plus étroites quand il y a 4 tours (planche à 16 joueurs).
        let widths: [CGFloat] = (0..<side).map { $0 == side - 1 && side >= 3 ? 210 : colW }
        let inner = widths.reduce(0, +) + CGFloat(side) * gap
        let width = 2 * inner + finalW
        let x0 = (areaW - width) / 2
        func offset(_ r: Int) -> CGFloat { widths.prefix(r).reduce(0, +) + CGFloat(r) * gap }
        var slots: [Slot] = []
        var cols: [(String, CGRect)] = []
        for (r, round) in info.rounds.enumerated() {
            let n = round.matches.count
            if n == 1 {
                slots.append(Slot(match: round.matches[0], frame: CGRect(x: x0 + inner, y: areaH / 2 - cardH / 2, width: finalW, height: cardH), right: false))
                continue
            }
            let half = n / 2
            let w = widths[r]
            for (k, right) in [false, true].enumerated() {
                let x = right ? x0 + width - offset(r) - w : x0 + offset(r)
                cols.append((round.name, CGRect(x: x, y: -6, width: w, height: 28)))
                for i in 0..<half {
                    let m = round.matches[k * half + i]
                    let cy = (CGFloat(i) + 0.5) * areaH / CGFloat(half)
                    slots.append(Slot(match: m, frame: CGRect(x: x, y: cy - cardH / 2, width: w, height: cardH), right: right))
                }
            }
        }
        return (slots, cols)
    }

    private var bracket: some View {
        let (slots, cols) = layout
        let live = info.focus?.state == "direct" ? info.focus?.id : nil
        return ZStack(alignment: .topLeading) {
            ForEach(cols.indices, id: \.self) { i in
                Text(cols[i].0).font(.td(22, .semibold)).foregroundStyle(Td.ink3)
                    .frame(width: cols[i].1.width)
                    .offset(x: cols[i].1.minX, y: cols[i].1.minY)
            }
            Canvas { ctx, _ in
                for s in slots {
                    guard let parent = parent(of: s.match, in: slots) else { continue }
                    let from = CGPoint(x: s.right ? s.frame.minX : s.frame.maxX, y: s.frame.midY)
                    let to = CGPoint(x: s.right ? parent.frame.maxX : parent.frame.minX, y: parent.frame.midY)
                    let mid = (from.x + to.x) / 2
                    var p = Path()
                    p.move(to: from)
                    p.addLine(to: CGPoint(x: mid, y: from.y))
                    p.addLine(to: CGPoint(x: mid, y: to.y))
                    p.addLine(to: to)
                    let hot = parent.match.id == live
                    ctx.stroke(p, with: .color(hot ? Td.fluo : Color.white.opacity(0.22)), lineWidth: 3)
                }
            }
            .frame(width: areaW, height: areaH)
            if let finale = slots.first(where: { $0.match.id == info.rounds.last?.matches.first?.id }) {
                VStack(spacing: 10) {
                    Icon(name: .trophy, size: 56).foregroundStyle(Td.fluo)
                    Text("Finale")
                        .font(.custom("PermanentMarker-Regular", size: 56))
                        .foregroundStyle(Td.sunset)
                        .shadow(color: Td.sunset.opacity(0.45), radius: 16)
                }
                .frame(width: finale.frame.width)
                .offset(x: finale.frame.minX, y: finale.frame.minY - 150)
            }
            ForEach(slots, id: \.match.id) { s in
                TVBracketCard(match: s.match, live: s.match.id == live, next: s.match.id == info.next && s.match.id != live,
                              champion: info.champion?.id)
                    .frame(width: s.frame.width, height: s.frame.height)
                    .offset(x: s.frame.minX, y: s.frame.minY)
            }
        }
    }

    private func parent(of m: TournamentMatch, in slots: [Slot]) -> Slot? {
        guard let r = info.rounds.firstIndex(where: { $0.matches.contains { $0.id == m.id } }),
              r + 1 < info.rounds.count,
              let i = info.rounds[r].matches.firstIndex(where: { $0.id == m.id }) else { return nil }
        let up = info.rounds[r + 1].matches[i / 2]
        return slots.first { $0.match.id == up.id }
    }
}

/// Carte d'un match du tableau : deux lignes joueur, score en manches.
struct TVBracketCard: View {
    @EnvironmentObject var model: TVModel
    let match: TournamentMatch
    var live = false
    var next = false
    var champion: String?

    private var pending: Bool { match.state == "attente" && !next }

    var body: some View {
        VStack(spacing: 0) {
            row(match.a, match.scoreA)
            Rectangle().fill(Td.bord).frame(height: 1)
            row(match.b, match.scoreB)
        }
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(pending ? Td.verreLeger : Td.verreMoyen))
        .overlay {
            if live {
                RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.fluo, lineWidth: 3)
                    .shadow(color: Td.fluo.opacity(0.5), radius: 16)
            } else if next {
                RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.sunset, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            } else if pending {
                RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.bordControle, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            } else {
                RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.verreBord)
            }
        }
        .overlay(alignment: .topLeading) {
            if live || next {
                Text(live ? "En direct" : "Prochain match")
                    .font(.td(20, .bold))
                    .foregroundStyle(live ? Td.fluo : Td.sunset)
                    .fixedSize()
                    .offset(y: -34)
            }
        }
    }

    private func row(_ p: TournamentPlayer?, _ score: Int) -> some View {
        let done = match.state == "fini"
        let won = p != nil && match.winner == p?.id
        let liveScore = live ? model.info?.game?.players.first { $0.name == p?.name }?.legs : nil
        return HStack(spacing: Td.s3) {
            if let p {
                TVAvatar(name: p.name, url: model.base.flatMap { p.photoURL(base: $0) }, size: 36)
                Text(p.name).font(.td(24, won || p.id == champion ? .heavy : .semibold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if done {
                    Text("\(score)").font(.tdRounded(30, .black)).foregroundStyle(won ? Td.sunset : Td.ink)
                } else if let liveScore {
                    Text("\(liveScore)").font(.tdRounded(30, .black)).foregroundStyle(Td.fluo)
                }
            } else {
                Circle().strokeBorder(Td.bordControle, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .frame(width: 36, height: 36)
                Text(match.state == "gratuit" ? "Place libre" : "À venir").font(.td(24)).foregroundStyle(Td.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Td.s4)
        .frame(maxHeight: .infinity)
        .opacity(done && !won ? 0.42 : 1)
    }
}

/// Annonce du match : "Demi-finale", les deux joueurs, "contre".
struct TVTournamentMatchView: View {
    @EnvironmentObject var model: TVModel
    let info: TournamentInfo
    let match: TournamentMatch

    var body: some View {
        VStack(spacing: 40) {
            Text(info.round(of: match)?.title ?? "")
                .font(.custom("PermanentMarker-Regular", size: 120))
                .foregroundStyle(Td.sunset)
                .shadow(color: Td.sunset.opacity(0.45), radius: 16)
                .rotationEffect(.degrees(-3))
            HStack(spacing: 120) {
                side(match.a)
                Text("contre")
                    .font(.custom("PermanentMarker-Regular", size: 89))
                    .foregroundStyle(Td.fluo)
                    .shadow(color: Td.fluo.opacity(0.4), radius: 10)
                    .rotationEffect(.degrees(-6))
                side(match.b)
            }
            Text("\(info.modeLabel) · \(info.legsLabel) · \(match.a?.name ?? "") commence")
                .font(.td(34)).foregroundStyle(Td.ink2)
            if let after = info.after(match) {
                Text(after).font(.td(22)).foregroundStyle(Td.ink3)
            }
        }
        .padding(.horizontal, 90).padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func side(_ p: TournamentPlayer?) -> some View {
        VStack(spacing: 60) {
            TVAvatar(name: p?.name ?? "?", url: p.flatMap { pl in model.base.flatMap { pl.photoURL(base: $0) } }, size: 280)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 4))
                .shadow(color: .black.opacity(0.6), radius: 32, y: 24)
            VStack(spacing: Td.s4) {
                Text(p?.name ?? "").font(.td(64, .heavy)).tracking(-0.5).lineLimit(1)
                Text(p.flatMap { info.lastWin($0.id) } ?? " ").font(.td(28)).foregroundStyle(Td.ink2)
            }
        }
        .frame(width: 520)
    }
}
