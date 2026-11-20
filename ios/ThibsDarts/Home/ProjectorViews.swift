import SwiftUI
import UIKit

/// État de la calibration guidée renvoyé par le Pi 5 (via le hub, /api/projector/guide).
struct ProjectorGuide: Decodable {
    struct Target: Decodable {
        let id: String
        let where_: String
        let hint: String
        let ring: String?

        enum CodingKeys: String, CodingKey { case id, hint, ring, where_ = "where" }
    }
    struct Err: Decodable { let mean: Double; let max: Double }

    let tab: String
    let index: Int
    let count: Int
    let target: Target
    /// Par point, dans l'ordre : "done", "skip" ou "".
    let status: [String]
    let fixed: Int
    let error: Err?
    let rings: [String: Double]
    let message: String?
    let ptr: [Double]?
}

/// Profil > Projecteur (propriétaire) : calibration du vidéoprojecteur depuis l'iPhone.
/// L'écran sert de pavé tactile : on fait glisser les fils projetés sur les vrais fils de la cible.
struct ProjectorCalibView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var guide: ProjectorGuide?
    @State private var error: String?
    @State private var fine = true
    @State private var lastDrag: CGSize = .zero
    /// Position de la croix tenue localement : chaque geste l'envoie en absolu, sans attendre la réponse.
    @State private var ptr: CGPoint?
    @State private var seq = 0
    @State private var inFlight = 0
    @State private var dirty = false
    @State private var confirmReset = false

    var body: some View {
        Stage {
            VStack(spacing: Td.s3) {
                NavBar(title: "Projecteur", back: "Retour") { leave() }
                tabs
                if let error { Banner(text: error, error: true) }
                if let g = guide {
                    switch g.tab {
                    case "points": points(g)
                    case "check": check(g)
                    default: frame
                    }
                } else if error == nil {
                    ProgressView().tint(Td.sunset).frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
            .padding(.bottom, Td.s3)
        }
        .task { await load() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    // MARK: Onglets

    private var tabs: some View {
        HStack(spacing: Td.s2) {
            tab("Cadrage", "frame")
            tab("Points", "points")
            tab("Vérifier", "check")
        }
    }

    private func tab(_ title: String, _ id: String) -> some View {
        let on = guide?.tab == id
        return Button { Task { await send(["action": "tab", "tab": id]) } } label: {
            Text(title)
                .font(.td(15, .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(on ? Td.onAccent : Td.ink)
                .background(RoundedRectangle(cornerRadius: Td.rSm).fill(on ? Td.sunset : Td.verreLeger))
                .overlay(RoundedRectangle(cornerRadius: Td.rSm).strokeBorder(on ? Td.sunset : Td.verreBord))
        }
        .buttonStyle(.plain)
    }

    private var frame: some View {
        VStack(alignment: .leading, spacing: Td.s3) {
            Text("Mire plein écran sur le projecteur.").font(.td(17, .semibold))
            Text("Cercle rose : place de la cible par défaut. Bord rose : limite de l'image.")
                .font(.td(15)).foregroundStyle(Td.ink2)
            Spacer()
            TdButton(title: "Commencer les points", icon: .crosshair, block: true) {
                Task { await send(["action": "tab", "tab": "points"]) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Points

    private func points(_ g: ProjectorGuide) -> some View {
        VStack(spacing: Td.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Point \(g.index + 1) / \(g.count)").font(.td(12, .semibold)).foregroundStyle(Td.ink3)
                Text(g.target.where_).font(.td(20, .semibold))
                Text(g.target.hint).font(.td(14)).foregroundStyle(Td.ink2)
                if let m = g.message { Text(m).font(.td(14, .semibold)).foregroundStyle(Td.erreur) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            pad

            HStack(spacing: Td.s2) {
                nudge(.chevronLeft, -1, 0)
                nudge(.chevronLeft, 0, -1, rotate: 90)
                nudge(.chevronRight, 0, 1, rotate: 90)
                nudge(.chevronRight, 1, 0)
            }
            HStack(spacing: Td.s2) {
                TdButton(title: fine ? "Précis" : "Rapide", variant: .secondary, block: true) { fine.toggle() }
                TdButton(title: "Passer", variant: .secondary, block: true) { Task { await send(["action": "skip"]) } }
                TdButton(title: "Valider", icon: .check, block: true) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await send(["action": "ok"]) }
                }
            }
            dots(g)
        }
    }

    /// Pavé tactile : déplacement relatif, 1 px projeté pour 4 pt de doigt en mode Précis.
    private var pad: some View {
        RoundedRectangle(cornerRadius: Td.rLg)
            .fill(Td.verreLeger)
            .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.fluo.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 6])))
            .overlay(Text("Glisse pour déplacer").font(.td(13)).foregroundStyle(Td.ink3))
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let d = CGSize(width: v.translation.width - lastDrag.width, height: v.translation.height - lastDrag.height)
                        lastDrag = v.translation
                        let k: CGFloat = fine ? 0.25 : 1.5
                        move(d.width * k, d.height * k)
                    }
                    .onEnded { _ in lastDrag = .zero }
            )
    }

    private func nudge(_ icon: LucideIcon, _ dx: CGFloat, _ dy: CGFloat, rotate: Double = 0) -> some View {
        Button { move(dx, dy) } label: {
            Icon(name: icon, size: 20)
                .rotationEffect(.degrees(rotate))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Td.rSm).fill(Td.verreLeger))
                .overlay(RoundedRectangle(cornerRadius: Td.rSm).strokeBorder(Td.verreBord))
        }
        .buttonStyle(.plain)
    }

    private func dots(_ g: ProjectorGuide) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 12), spacing: 4) {
            ForEach(0..<g.count, id: \.self) { i in
                let done = i < g.status.count && g.status[i] == "done"
                Button { Task { await send(["action": "goto", "index": i]) } } label: {
                    Text("\(i + 1)")
                        .font(.td(11, .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(i == g.index ? Td.fluo : done ? Td.succes : Td.ink3)
                        .background(Circle().fill(done ? Td.succesFond : .clear))
                        .overlay(Circle().strokeBorder(i == g.index ? Td.fluo : done ? Td.succes : Td.verreBord))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Vérifier

    private func check(_ g: ProjectorGuide) -> some View {
        VStack(alignment: .leading, spacing: Td.s3) {
            Text("Mire sur la cible").font(.td(17, .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("\(g.fixed) points de la cible").font(.td(15))
                if let e = g.error {
                    Text("Écart moyen \(fmt(e.mean)) px, max \(fmt(e.max)) px").font(.td(15))
                }
                ForEach(g.rings.sorted(by: { $0.key < $1.key }), id: \.key) { item in
                    Text("\(item.key) : \(fmt(item.value)) mm").font(.td(15)).foregroundStyle(Td.ink2)
                }
            }
            HStack(spacing: Td.s2) {
                ForEach(["T20", "D16", "DB", "180"], id: \.self) { k in
                    TdButton(title: k == "DB" ? "Bull" : k, variant: .secondary, size: .sm, block: true) {
                        Task { await test(k) }
                    }
                }
            }
            Text("La calibration est enregistrée à chaque point validé.").font(.td(14)).foregroundStyle(Td.ink3)
            Spacer()
            HStack(spacing: Td.s2) {
                TdButton(title: "Refaire les points", variant: .secondary, block: true) { Task { await send(["action": "redo"]) } }
                TdButton(title: "Par défaut", variant: .tertiary, block: true) { confirmReset = true }
            }
            TdButton(title: "Terminer", icon: .check, block: true) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                leave()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("Effacer la calibration ?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Revenir au réglage par défaut", role: .destructive) { Task { await send(["action": "reset"]) } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous les points validés seront perdus.")
        }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }

    // MARK: Réseau

    /// Déplacement : la croix bouge tout de suite côté iPhone, la position absolue part au Pi 5 avec
    /// un numéro croissant (au plus 3 envois en vol, le dernier l'emporte, un envoi en retard est ignoré).
    private func move(_ dx: CGFloat, _ dy: CGFloat) {
        guard var p = ptr else { return }
        p.x += dx
        p.y += dy
        ptr = p
        flush()
    }

    private func flush() {
        guard let p = ptr else { return }
        if inFlight >= 3 { dirty = true; return }
        dirty = false
        seq += 1
        inFlight += 1
        guard let req = request("guide", ["action": "set", "x": Double(p.x), "y": Double(p.y), "seq": seq]) else { inFlight -= 1; return }
        Task {
            _ = try? await URLSession.shared.data(for: req)
            inFlight -= 1
            if dirty { flush() }
        }
    }

    private func request(_ path: String, _ body: [String: Any]?) -> URLRequest? {
        guard let base = app.piBase else { return nil }
        var req = URLRequest(url: base.appendingPathComponent("api/projector/\(path)"))
        req.timeoutInterval = 6
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        app.authorize(&req)
        return req
    }

    private func load() async {
        guard let req = request("guide", nil) else { error = "Pas de Pi 4 trouvé."; return }
        await run(req)
        if guide?.tab != "points" { await send(["action": "tab", "tab": guide?.tab ?? "frame"]) }
    }

    private func send(_ body: [String: Any], quiet: Bool = false) async {
        guard let req = request("guide", body) else { return }
        await run(req, quiet: quiet)
    }

    private func run(_ req: URLRequest, quiet: Bool = false) async {
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            switch (res as? HTTPURLResponse)?.statusCode {
            case 200:
                let g = try JSONDecoder().decode(ProjectorGuide.self, from: data)
                if quiet, let cur = guide, cur.index == g.index, cur.tab == g.tab { return }
                guide = g
                if let p = g.ptr, p.count == 2, inFlight == 0 { ptr = CGPoint(x: p[0], y: p[1]) }
                error = nil
            case 401: error = "Réservé au propriétaire de la cible."
            default: error = "Le Pi 5 du projecteur ne répond pas."
            }
        } catch {
            if !quiet { self.error = "Le Pi 5 du projecteur ne répond pas." }
        }
    }

    private func test(_ kind: String) async {
        guard let req = request("test", ["kind": kind]) else { return }
        _ = try? await URLSession.shared.data(for: req)
    }

    private func leave() {
        Task {
            await send(["action": "leave"])
            dismiss()
        }
    }
}
