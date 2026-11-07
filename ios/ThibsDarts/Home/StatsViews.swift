import SwiftUI

// Onglets Stats et Historique (planches Stats et Historique), nourris par l'historique du Pi.

// MARK: Données

struct HistoryTurn: Decodable, Hashable {
    let leg: Int?
    let darts: [String]
    let total: Int
    let rest: Int
    let bust: Bool
}

struct HistoryPlayer: Decodable, Hashable {
    let id: String
    let name: String
    let won: Bool
    var darts: Int?
    // X01
    var scored: Int?
    var best: Int?
    var tries: Int?
    var hits: Int?
    var turns: [HistoryTurn]?
    // Autres modes
    var score: Int?
    /// Valeur affichée dans la liste (moyenne, marques par tour, points, vies) et son libellé.
    var value: Double?
    var valueLabel: String?

    var average: Double? {
        guard let scored, let darts, darts > 0 else { return nil }
        return Double(scored) / Double(darts) * 3
    }
}

struct HistoryMatch: Decodable, Identifiable, Hashable {
    let id: String
    let at: String
    let mode: String
    let kind: String
    let winner: String?
    let players: [HistoryPlayer]

    var isX01: Bool { kind == "x01" }
    var isDraw: Bool { winner?.contains(" et ") == true }

    var date: Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(at.prefix(19))) ?? .distantPast
    }

    func me(_ id: String) -> HistoryPlayer? { players.first { $0.id == id } }

    /// "Thibs", "Thibs et Max", ou nil en solo.
    func opponents(_ id: String) -> String? {
        let others = players.filter { $0.id != id }.map(\.name)
        guard !others.isEmpty else { return nil }
        if others.count == 1 { return others[0] }
        return others.dropLast().joined(separator: ", ") + " et " + others.last!
    }

    func title(_ id: String) -> String {
        opponents(id).map { "\(mode) contre \($0)" } ?? "\(mode) en solo"
    }
}

private struct HistoryList: Decodable { let matches: [HistoryMatch] }

extension LobbyAPI {
    static func history(at base: URL, player: String) async throws -> [HistoryMatch] {
        var c = URLComponents(url: base.appendingPathComponent("api/history"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "player", value: player)]
        let (data, res) = try await session.data(from: c.url!)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw PiError.unreachable }
        return try JSONDecoder().decode(HistoryList.self, from: data).matches
    }

    static func match(at base: URL, id: String) async throws -> HistoryMatch {
        let (data, res) = try await session.data(from: base.appendingPathComponent("api/history/\(id)"))
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw PiError.unreachable }
        return try JSONDecoder().decode(HistoryMatch.self, from: data)
    }
}

/// Historique du joueur de ce téléphone, chargé depuis le Pi.
@MainActor
final class HistoryModel: ObservableObject {
    enum State { case loading, ready, error, noPi }

    @Published private(set) var state: State = .loading
    @Published private(set) var matches: [HistoryMatch] = []

    func load(app: AppModel) async {
        guard let base = app.piBase else {
            state = .noPi
            return
        }
        if matches.isEmpty { state = .loading }
        do {
            matches = try await LobbyAPI.history(at: base, player: app.playerId)
            state = .ready
        } catch {
            if matches.isEmpty { state = .error }
        }
    }
}

extension AppModel {
    /// Identifiant du joueur dans l'historique du Pi : "owner" pour le propriétaire, sinon ce téléphone.
    var playerId: String { profileId ?? (isOwner ? "owner" : deviceId) }
}

// MARK: Format

func frDecimal(_ v: Double) -> String {
    String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
}

func frSigned(_ v: Double) -> String {
    (v >= 0 ? "+" : "-") + frDecimal(abs(v))
}

/// "Aujourd'hui, 23 h 12", "Hier, 22 h 40", "31 oct."
func frMatchDate(_ d: Date, now: Date = .now) -> String {
    let cal = Calendar.current
    let t = DateFormatter()
    t.locale = Locale(identifier: "fr_FR")
    t.dateFormat = "H\u{00A0}'h'\u{00A0}mm"
    if cal.isDate(d, inSameDayAs: now) { return "Aujourd’hui, \(t.string(from: d))" }
    if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(d, inSameDayAs: y) {
        return "Hier, \(t.string(from: d))"
    }
    let f = DateFormatter()
    f.locale = Locale(identifier: "fr_FR")
    f.dateFormat = cal.isDate(d, equalTo: now, toGranularity: .year) ? "d MMM" : "d MMM yyyy"
    return f.string(from: d)
}

// MARK: Composants (KpiTile, SegmentedControl, Chip, LineChart, MatchHistory)

struct KpiTile: View {
    enum Trend { case up, down }
    let label: String
    let value: String
    var unit: String?
    var delta: String?
    var trend: Trend?
    var empty = false

    var body: some View {
        VStack(alignment: .leading, spacing: Td.s1) {
            Text(label).font(.td(13, .medium)).foregroundStyle(Td.ink2).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(empty ? "00" : value).font(.tdRounded(48, .heavy)).monospacedDigit()
                    .foregroundStyle(empty ? Td.ink3 : Td.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit, !empty { Text(unit).font(.tdRounded(22, .bold)).foregroundStyle(Td.ink2) }
            }
            .frame(height: 52)
            if empty {
                Text("Pas encore joué").font(.td(13)).foregroundStyle(Td.ink2)
            } else if let delta {
                HStack(spacing: Td.s1) {
                    if let trend {
                        Text(trend == .up ? "▲" : "▼").foregroundStyle(trend == .up ? Td.succes : Td.erreur)
                    }
                    Text(delta)
                }
                .font(.td(13)).foregroundStyle(Td.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Td.s4)
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.asphalte))
        .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.bord))
    }
}

struct SegmentedControl: View {
    let options: [String]
    @Binding var value: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                Button {
                    withAnimation(Td.sortie) { value = o }
                } label: {
                    Text(o).font(.td(15, .semibold))
                        .foregroundStyle(o == value ? Td.beton : Td.ink2)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: Td.rMd - 3).fill(o == value ? Td.ink : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScale())
                .accessibilityAddTraits(o == value ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: Td.rMd).fill(Td.verreLeger))
        .overlay(RoundedRectangle(cornerRadius: Td.rMd).strokeBorder(Td.verreBord))
    }
}

struct Chip: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text).font(.td(15, .medium)).foregroundStyle(Td.ink)
                .padding(.horizontal, Td.s3)
                .frame(height: 36)
                .background(Capsule().fill(selected ? Td.sunsetFond : Td.verreLeger))
                .overlay(Capsule().strokeBorder(selected ? Td.sunset : Td.verreBord))
        }
        .buttonStyle(PressScale())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Courbe d'une série (LineChart du design system) : grille, graduations, dernière valeur au bout.
struct LineChart: View {
    let labels: [String]
    let data: [Double]
    var height: CGFloat = 150

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pl: CGFloat = 36, pr: CGFloat = 44, pt: CGFloat = 12, pb: CGFloat = 24
            let rawLo = data.min() ?? 0, rawHi = data.max() ?? 1
            let step = [1.0, 2, 5, 10, 20, 50, 100].first { (rawHi - rawLo) / $0 <= 4 } ?? 100
            let lo = (rawLo / step).rounded(.down) * step
            let hi = max((rawHi / step).rounded(.up) * step, lo + step)
            let x = { (i: Int) -> CGFloat in pl + CGFloat(i) * (w - pl - pr) / CGFloat(max(labels.count - 1, 1)) }
            let y = { (v: Double) -> CGFloat in pt + CGFloat((hi - v) / (hi - lo)) * (h - pt - pb) }
            let ticks = Array(stride(from: lo, through: hi + 0.0001, by: step))
            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { t in
                    Path { p in
                        p.move(to: CGPoint(x: pl, y: y(t)))
                        p.addLine(to: CGPoint(x: w - pr, y: y(t)))
                    }
                    .stroke(Td.bord, lineWidth: 1)
                    Text("\(Int(t.rounded()))").font(.td(12)).monospacedDigit().foregroundStyle(Td.ink3)
                        .frame(width: pl - 8, alignment: .trailing)
                        .position(x: (pl - 8) / 2, y: y(t))
                }
                let every = Int((Double(labels.count) / 7).rounded(.up))
                ForEach(Array(labels.enumerated()), id: \.offset) { i, l in
                    if i % max(every, 1) == 0 {
                        Text(l).font(.td(12)).foregroundStyle(Td.ink3).fixedSize().position(x: x(i), y: h - 8)
                    }
                }
                Path { p in
                    for (i, v) in data.enumerated() {
                        let pt = CGPoint(x: x(i), y: y(v))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Td.sunset, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let last = data.last {
                    Text(frDecimal(last)).font(.td(12, .semibold)).foregroundStyle(Td.ink).fixedSize()
                        .position(x: x(data.count - 1) + 8 + 16, y: y(last))
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Moyenne, de \(frDecimal(data.first ?? 0)) à \(frDecimal(data.last ?? 0))")
    }
}

/// État vide ou erreur d'un graphique ou d'une liste (ChartState).
struct ChartState: View {
    let icon: LucideIcon
    let text: String
    var error = false
    var onRetry: (() -> Void)?
    var minHeight: CGFloat = 180

    var body: some View {
        VStack(spacing: Td.s2) {
            Icon(name: icon, size: 24).foregroundStyle(error ? Td.erreur : Td.ink2)
            Text(text).font(.td(15)).multilineTextAlignment(.center).foregroundStyle(error ? Td.ink : Td.ink2)
            if let onRetry {
                TdButton(title: "Réessayer", variant: .secondary, size: .sm, icon: .refreshCw, action: onRetry)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(Td.s4)
        .overlay(
            RoundedRectangle(cornerRadius: Td.rMd)
                .strokeBorder(Td.bord, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

struct MatchRow: View {
    let match: HistoryMatch
    let me: String
    var selected = false

    var body: some View {
        let p = match.me(me)
        HStack(spacing: Td.s3) {
            Avatar(name: match.opponents(me) ?? p?.name ?? "?", size: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text(match.title(me)).font(.td(15, .semibold)).foregroundStyle(Td.ink).lineLimit(1)
                Text(frMatchDate(match.date)).font(.td(13)).foregroundStyle(Td.ink3).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if match.isDraw, p?.won == true {
                Badge(text: "Égalité", tone: .info)
            } else {
                Badge(text: p?.won == true ? "Gagné" : "Perdu", tone: p?.won == true ? .succes : .neutre)
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text(p?.value.map(rowValue) ?? "-").font(.tdRounded(22, .heavy)).monospacedDigit().foregroundStyle(Td.ink)
                Text(p?.valueLabel ?? "").font(.td(12, .medium)).foregroundStyle(Td.ink3)
            }
            .fixedSize()
            Icon(name: .chevronRight, size: 18).foregroundStyle(Td.ink3)
        }
        .padding(.vertical, Td.s3).padding(.horizontal, Td.s4)
        .frame(minHeight: 60)
        .background(selected ? Td.asphalteHaut : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func rowValue(_ v: Double) -> String {
        v == v.rounded() && match.kind != "x01" && match.kind != "cricket" ? "\(Int(v))" : frDecimal(v)
    }
}

/// Liste de parties (MatchHistory) : un bloc asphalte, une ligne par partie.
struct MatchHistoryList: View {
    let matches: [HistoryMatch]
    let me: String
    var onSelect: (HistoryMatch) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element.id) { i, m in
                if i > 0 { Td.bord.frame(height: 1) }
                Button { onSelect(m) } label: { MatchRow(match: m, me: me) }
                    .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.asphalte))
        .clipShape(RoundedRectangle(cornerRadius: Td.rLg))
        .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.bord))
    }
}

// MARK: Onglet Stats

struct StatsTab: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var history: HistoryModel
    @State private var period = "30 jours"

    private var days: Int? { period == "7 jours" ? 7 : (period == "30 jours" ? 30 : nil) }

    private func inPeriod(_ m: HistoryMatch, back: Int = 0) -> Bool {
        guard let days else { return back == 0 }
        let end = Calendar.current.date(byAdding: .day, value: -days * back, to: .now)!
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end)!
        return m.date > start && m.date <= end
    }

    private struct Numbers {
        var games = 0, won = 0, darts = 0, scored = 0, best = 0, tries = 0, hits = 0
        var avg: Double? { darts > 0 ? Double(scored) / Double(darts) * 3 : nil }
        var checkout: Double? { tries > 0 ? Double(hits) * 100 / Double(tries) : nil }
    }

    private func numbers(back: Int = 0) -> Numbers {
        var n = Numbers()
        for m in history.matches where inPeriod(m, back: back) {
            guard let p = m.me(app.playerId) else { continue }
            n.games += 1
            if p.won { n.won += 1 }
            if m.isX01 {
                n.darts += p.darts ?? 0
                n.scored += p.scored ?? 0
                n.best = max(n.best, p.best ?? 0)
                n.tries += p.tries ?? 0
                n.hits += p.hits ?? 0
            }
        }
        return n
    }

    private var deltaWord: String { days == 7 ? "cette semaine" : "ce mois" }

    var body: some View {
        Stage {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tes stats").font(.td(34, .heavy)).tracking(-0.5)
                    switch history.state {
                    case .noPi:
                        ChartState(icon: .target, text: "Rejoins un salon pour relier ton iPhone à la cible.")
                    case .error:
                        ChartState(icon: .circleAlert, text: "Le Pi ne répond pas.", error: true) {
                            Task { await history.load(app: app) }
                        }
                    default:
                        content
                    }
                }
                .padding(.horizontal, Td.s4)
                .padding(.top, Td.s4)
                .padding(.bottom, 120)
            }
            .refreshable { await history.load(app: app) }
        }
    }

    @ViewBuilder private var content: some View {
        let n = numbers()
        let prev = days == nil ? nil : numbers(back: 1)
        SegmentedControl(options: ["7 jours", "30 jours", "Tout"], value: $period)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Td.s2), GridItem(.flexible())], spacing: Td.s2) {
            avgTile(n, prev)
            checkoutTile(n, prev)
            KpiTile(label: "Meilleur tour", value: "\(n.best)", empty: n.darts == 0)
            KpiTile(label: "Parties gagnées", value: "\(n.won)", unit: "/\(n.games)", empty: n.games == 0)
        }
        chart
    }

    private func avgTile(_ n: Numbers, _ prev: Numbers?) -> KpiTile {
        guard let a = n.avg else { return KpiTile(label: "Moyenne 3 fléchettes", value: "", empty: true) }
        if let p = prev?.avg {
            let d = a - p
            return KpiTile(label: "Moyenne 3 fléchettes", value: frDecimal(a), delta: "\(frSigned(d)) \(deltaWord)", trend: d >= 0 ? .up : .down)
        }
        return KpiTile(label: "Moyenne 3 fléchettes", value: frDecimal(a))
    }

    private func checkoutTile(_ n: Numbers, _ prev: Numbers?) -> KpiTile {
        guard let c = n.checkout else { return KpiTile(label: "Checkout", value: "", empty: true) }
        if let p = prev?.checkout {
            let d = Int(c.rounded()) - Int(p.rounded())
            return KpiTile(label: "Checkout", value: "\(Int(c.rounded()))", unit: "%",
                           delta: "\(d >= 0 ? "+" : "-")\(abs(d)) point\(abs(d) > 1 ? "s" : "")", trend: d >= 0 ? .up : .down)
        }
        return KpiTile(label: "Checkout", value: "\(Int(c.rounded()))", unit: "%")
    }

    /// Moyenne de chaque partie X01 de la période, de la plus ancienne à la plus récente.
    @ViewBuilder private var chart: some View {
        let games = history.matches.filter { $0.isX01 && inPeriod($0) }.reversed()
            .compactMap { m in m.me(app.playerId)?.average.map { (m.date, $0) } }
        VStack(alignment: .leading, spacing: Td.s1) {
            Text("Ta moyenne, partie après partie").font(.td(13, .semibold)).foregroundStyle(Td.ink2)
            if games.count < 2 {
                ChartState(icon: .chartLine, text: "Rien à tracer. Lance quelques fléchettes.", minHeight: 120)
            } else {
                let f: DateFormatter = {
                    let f = DateFormatter()
                    f.dateFormat = "dd/MM"
                    return f
                }()
                let raw = games.map { f.string(from: $0.0) }
                // Une date par jour : les parties suivantes du même jour n'ont pas d'étiquette.
                let labels = raw.enumerated().map { i, l in i > 0 && raw[i - 1] == l ? "" : l }
                LineChart(labels: labels, data: games.map(\.1))
            }
        }
        .padding(Td.s3)
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.asphalte))
        .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.bord))
    }
}

// MARK: Onglet Historique

struct HistoryTab: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var history: HistoryModel
    @State private var filter = "Tout"
    @State private var detail: HistoryMatch?

    private var modes: [String] {
        // Ordre des planches : X01, puis Cricket, Killer et les autres modes.
        let order = ["501", "301", "Cricket", "Killer", "Shanghai", "Around the clock", "Halve-it", "Bob's 27"]
        let played = Set(history.matches.map(\.mode))
        return ["Tout"] + played.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
    }

    var body: some View {
        Stage {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Historique").font(.td(34, .heavy)).tracking(-0.5)
                    switch history.state {
                    case .loading:
                        HStack { Spacer(); Spinner(size: 24); Spacer() }.padding(Td.s6)
                    case .noPi:
                        ChartState(icon: .target, text: "Rejoins un salon pour relier ton iPhone à la cible.")
                    case .error:
                        ChartState(icon: .circleAlert, text: "L’historique n’a pas chargé.", error: true) {
                            Task { await history.load(app: app) }
                        }
                    case .ready:
                        if history.matches.isEmpty {
                            ChartState(icon: .history, text: "Aucune partie. Le minimum, c’est d’en lancer une.")
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Td.s2) {
                                    ForEach(modes, id: \.self) { m in
                                        Chip(text: m, selected: filter == m) { filter = m }
                                    }
                                }
                            }
                            MatchHistoryList(
                                matches: history.matches.filter { filter == "Tout" || $0.mode == filter },
                                me: app.playerId
                            ) { detail = $0 }
                        }
                    }
                }
                .padding(.horizontal, Td.s4)
                .padding(.top, Td.s4)
                .padding(.bottom, 120)
            }
            .refreshable { await history.load(app: app) }
        }
        .sheet(item: $detail) { m in
            MatchDetailView(match: m).environmentObject(app)
                .presentationDetents([.medium, .large])
                .presentationBackground(Td.beton)
        }
    }
}

/// Détail d'une partie (MatchDetail) : stats et, en X01, chaque tour.
struct MatchDetailView: View {
    @EnvironmentObject var app: AppModel
    let match: HistoryMatch
    @State private var full: HistoryMatch?

    private var me: HistoryPlayer? { (full ?? match).me(app.playerId) }

    private var stats: [(String, String)] {
        guard let p = me else { return [] }
        if match.isX01 {
            var s = [("Moyenne", p.average.map(frDecimal) ?? "-"), ("Meilleur tour", "\(p.best ?? 0)")]
            if let t = p.tries, t > 0 { s.append(("Checkout", "\(Int((Double(p.hits ?? 0) * 100 / Double(t)).rounded())) %")) }
            s.append(("Fléchettes", "\(p.darts ?? 0)"))
            return s
        }
        var s: [(String, String)] = []
        if match.kind == "cricket", let v = p.value { s.append(("Marques par tour", frDecimal(v))) }
        if let sc = p.score { s.append((match.kind == "killer" ? "Vies" : "Score", "\(sc)")) }
        s.append(("Fléchettes", "\(p.darts ?? 0)"))
        return s
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Td.s4) {
                HStack(alignment: .top, spacing: Td.s3) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(match.title(app.playerId)).font(.td(22, .bold))
                        Text(frMatchDate(match.date)).font(.td(13)).foregroundStyle(Td.ink3)
                    }
                    Spacer()
                    Badge(text: me?.won == true ? "Gagné" : "Perdu", tone: me?.won == true ? .succes : .neutre)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Td.s3)], alignment: .leading, spacing: Td.s3) {
                    ForEach(stats, id: \.0) { s in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.0).font(.td(12)).foregroundStyle(Td.ink3)
                            Text(s.1).font(.tdRounded(28, .heavy)).monospacedDigit()
                        }
                    }
                }
                if match.isX01 {
                    if let turns = me?.turns, !turns.isEmpty {
                        turnsTable(turns)
                    } else if full == nil {
                        HStack { Spacer(); Spinner(size: 20); Spacer() }
                    }
                }
            }
            .padding(Td.s5)
            .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.asphalte))
            .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.bord))
            .padding(Td.s4)
        }
        .foregroundStyle(Td.ink)
        .task {
            guard match.isX01, let base = app.piBase else { return }
            full = try? await LobbyAPI.match(at: base, id: match.id)
        }
    }

    private func turnsTable(_ turns: [HistoryTurn]) -> some View {
        let multiLeg = Set(turns.compactMap(\.leg)).count > 1
        return Grid(alignment: .trailing, horizontalSpacing: Td.s3, verticalSpacing: 0) {
            GridRow {
                Text("Tour").gridColumnAlignment(.leading)
                Text("F1"); Text("F2"); Text("F3"); Text("Total"); Text("Reste")
            }
            .font(.td(12, .semibold)).foregroundStyle(Td.ink3)
            .padding(.vertical, Td.s2)
            Divider().overlay(Td.bord)
            ForEach(Array(turns.enumerated()), id: \.offset) { i, t in
                let hi = t.total >= 100
                GridRow {
                    Text(multiLeg ? "M\(t.leg ?? 1) · \(i + 1)" : "\(i + 1)")
                    ForEach(0..<3, id: \.self) { k in Text(k < t.darts.count ? dartLabel(t.darts[k]) : "") }
                    Text(t.bust ? "Bust" : "\(t.total)")
                    Text("\(t.rest)")
                }
                .font(.td(15, hi ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(hi ? Td.sunset : (t.bust ? Td.erreur : Td.ink))
                .padding(.vertical, Td.s2)
                Divider().overlay(Td.bord)
            }
        }
    }

    private func dartLabel(_ l: String) -> String {
        if l == "MISS" { return "Raté" }
        if l == "BULL" { return "Bull" }
        return l.hasPrefix("S") ? String(l.dropFirst()) : l
    }
}
