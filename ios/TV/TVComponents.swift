import CoreImage.CIFilterBuiltins
import SwiftUI

// Composants du design system, taille TV (1920 x 1080 points).

/// Fond béton avec la lueur horizon.
struct TVStage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Td.beton.ignoresSafeArea()
            GeometryReader { geo in
                EllipticalGradient(
                    stops: [
                        .init(color: Td.sunset.opacity(0.30), location: 0),
                        .init(color: Td.crepuscule.opacity(0.14), location: 0.45),
                        .init(color: Td.beton.opacity(0), location: 0.75),
                    ],
                    center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5
                )
                .frame(width: geo.size.width * 2.4, height: geo.size.height * 1.4)
                .position(x: geo.size.width / 2, y: geo.size.height * 1.18)
            }
            .ignoresSafeArea()
            content
        }
    }
}

struct TVLogo: View {
    var height: CGFloat = 72
    var body: some View {
        Image("Logo").resizable().scaledToFit().frame(height: height).accessibilityLabel("ThibsDarts")
    }
}

/// Avatar rond : photo servie par le Pi, sinon initiales.
struct TVAvatar: View {
    let name: String
    var url: URL?
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            Circle().fill(Td.asphalteHaut)
            if let url {
                AsyncImage(url: url) { ph in
                    if let img = ph.image { img.resizable().scaledToFill() } else { initials }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Td.verreBord))
    }

    private var initials: some View {
        Text(String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased())
            .font(.tdRounded(size * 0.38, .heavy))
            .foregroundStyle(Td.ink)
    }
}

/// Ligne joueur (PlayerList, densité tv).
struct TVPlayerRow: View {
    let name: String
    var url: URL?
    var sub: String?
    var score: Int?
    var active = false
    var winner = false
    var ready = false

    var body: some View {
        HStack(spacing: Td.s4) {
            TVAvatar(name: name, url: url, size: 72)
                .overlay(Circle().strokeBorder(active ? Td.fluo : .clear, lineWidth: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.td(34, .semibold)).lineLimit(1)
                if let sub {
                    Text(sub).font(.td(24)).foregroundStyle(ready ? Td.succes : Td.ink2).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let score {
                Text("\(score)")
                    .font(.tdRounded(56, .heavy)).monospacedDigit()
                    .foregroundStyle(winner ? Td.succes : (active ? Td.ink : Td.ink2))
            }
        }
        .padding(.horizontal, Td.s5)
        .padding(.vertical, Td.s4)
        .background(RoundedRectangle(cornerRadius: Td.rXl).fill(active ? Td.verreMoyen : Td.verreLeger))
        .overlay(
            RoundedRectangle(cornerRadius: Td.rXl)
                .strokeBorder(active ? Td.fluo : (winner || ready ? Td.succes : Td.verreBord), lineWidth: active ? 2 : 1)
        )
        .shadow(color: active ? Td.fluo.opacity(0.4) : .clear, radius: 20)
    }
}

/// Gros score (ScoreDisplay, taille xl).
struct TVScore: View {
    let value: Int
    let label: String
    var sub: String?
    var out = false
    var bust = false
    var size: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: Td.s2) {
            Text(label).font(.td(28, .semibold)).foregroundStyle(Td.ink2)
            Text("\(value)")
                .font(.tdRounded(size, .black)).monospacedDigit()
                .tracking(-size / 32)
                .foregroundStyle(bust ? AnyShapeStyle(Td.erreur) : (out ? AnyShapeStyle(Td.goldenHour) : AnyShapeStyle(Td.ink)))
                .lineLimit(1).minimumScaleFactor(0.5)
            if let sub {
                Text(sub).font(.td(28, bust ? .semibold : .regular)).foregroundStyle(bust ? Td.erreur : Td.ink2)
            }
        }
    }
}

/// Trois cases de fléchettes (DartSlots, taille xl).
struct TVDartSlots: View {
    let darts: [LiveDart]
    var closed = false

    var body: some View {
        HStack(spacing: Td.s3) {
            ForEach(0..<3, id: \.self) { i in
                slot(i)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            }
        }
    }

    @ViewBuilder private func slot(_ i: Int) -> some View {
        if i < darts.count {
            let d = darts[i]
            let miss = d.label == "MISS" || d.value == 0
            VStack(spacing: 0) {
                Text(miss ? "Raté" : d.label).font(.tdRounded(52, .heavy)).foregroundStyle(miss ? Td.erreur : Td.ink)
                Text("\(d.value)").font(.td(24)).foregroundStyle(Td.ink2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.verreMoyen))
            .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.verreBord))
        } else if i == darts.count && !closed {
            Icon(name: .crosshair, size: 52)
                .foregroundStyle(Td.fluo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.fluo.opacity(0.18)))
                .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.fluo, lineWidth: 2))
        } else {
            Text("\(i + 1)").font(.tdRounded(44, .heavy)).foregroundStyle(Td.ink3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: Td.rLg)
                        .strokeBorder(Td.bordControle, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                )
        }
    }
}

/// Sortie conseillée (CheckoutHint, taille tv).
struct TVCheckout: View {
    let route: [String]

    var body: some View {
        HStack(spacing: Td.s3) {
            Text("Sortie").font(.td(28, .semibold)).foregroundStyle(Td.ink2)
            ForEach(Array(route.enumerated()), id: \.offset) { i, r in
                if i > 0 { Icon(name: .chevronRight, size: 28).foregroundStyle(Td.ink3) }
                Text(r == "BULL" ? "Bull" : r.replacingOccurrences(of: "S", with: ""))
                    .font(.tdRounded(44, .heavy))
                    .padding(.horizontal, Td.s4).padding(.vertical, Td.s2)
                    .background(RoundedRectangle(cornerRadius: Td.rMd).fill(i == route.count - 1 ? Td.sunsetFond : Td.verreMoyen))
            }
        }
    }
}

/// QR code du salon (CoreImage), modules béton sur fond crème.
struct TVQRCode: View {
    let text: String
    var size: CGFloat = 300

    var body: some View {
        Group {
            if let img = Self.make(text) {
                Image(decorative: img, scale: 1).interpolation(.none).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 36).fill(Color(hex: 0xE8DCC4)))
        .shadow(color: Td.sunset.opacity(0.4), radius: 24)
        .accessibilityLabel("QR code pour rejoindre le salon")
    }

    static func make(_ text: String) -> CGImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let colored = out.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(red: 0x12 / 255, green: 0x12 / 255, blue: 0x14 / 255),
            "inputColor1": CIColor(red: 0xE8 / 255, green: 0xDC / 255, blue: 0xC4 / 255),
        ])
        return CIContext().createCGImage(colored, from: colored.extent)
    }
}

/// Tag bombé (HitTag) : Permanent Marker, dégradé golden hour, penché.
struct TVSprayTag: View {
    let text: String
    var size: CGFloat = 224
    var pink = false
    @State private var shown = false

    var body: some View {
        Text(text)
            .font(.custom("PermanentMarker-Regular", size: size))
            .foregroundStyle(Td.goldenHour)
            .background(
                RadialGradient(
                    colors: [(pink ? Td.crepuscule : Td.sunset).opacity(0.45), .clear],
                    center: .center, startRadius: 0, endRadius: size * 1.6
                )
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 0.5 : 0.9)
            )
            .mask(alignment: .leading) { Rectangle().scaleEffect(x: shown ? 1 : 0, anchor: .leading) }
            .scaleEffect(shown ? 1 : 1.14)
            .rotationEffect(.degrees(-5))
            .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
            .onAppear { withAnimation(.timingCurve(0.1, 0.9, 0.2, 1, duration: 0.9)) { shown = true } }
    }
}

/// Plateau (Dartboard) dessiné : les touches du tour en couleur, la sortie visée en bleu.
struct TVDartboard: View {
    var darts: [LiveDart] = []
    var aimed: String?
    var heat: Set<Int> = []

    static let sectors = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
    private static let rB = 6.35, rOb = 15.9, rTi = 99.0, rTo = 107.0, rDi = 162.0, rDo = 170.0

    /// "T20" -> (20, "T"), "S5" -> (5, "S"), "BULL" -> (25, "B"), "25" -> (25, "O").
    static func parse(_ label: String) -> (Int, String)? {
        if label == "BULL" { return (25, "B") }
        if label == "25" { return (25, "O") }
        guard let f = label.first, let n = Int(label.dropFirst()) else { return nil }
        return (n, String(f))
    }

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 410
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.scaleBy(x: s, y: s)
            let hits = Set(darts.compactMap { Self.parse($0.label) }.map { "\($0.0)\($0.1)" })
            let aim = aimed.flatMap(Self.parse).map { "\($0.0)\($0.1)" }
            ctx.fill(Path(ellipseIn: CGRect(x: -202, y: -202, width: 404, height: 404)), with: .color(Td.betonNuit))
            let wire = Color(hex: 0x3A3B42)
            for (i, sec) in Self.sectors.enumerated() {
                let a0 = Double(i) * 18 - 9, a1 = a0 + 18
                let even = i % 2 == 0
                for (ring, r0, r1) in [("S", Self.rOb, Self.rTi), ("T", Self.rTi, Self.rTo), ("S", Self.rTo, Self.rDi), ("D", Self.rDi, Self.rDo)] {
                    let p = Self.seg(r0, r1, a0, a1)
                    let key = "\(sec)\(ring)"
                    var c: Color = ring == "S" ? (even ? Color(hex: 0x17181C) : Color(hex: 0xE8DCC4)) : (even ? Color(hex: 0xE8434F) : Color(hex: 0x0C6A55))
                    if heat.contains(sec) { c = ring == "S" ? Td.sunset.opacity(0.75) : Td.sunset }
                    if hits.contains(key) {
                        ctx.fill(p, with: ring == "T" ? .linearGradient(Gradient(colors: [Td.sunset, Td.crepuscule]), startPoint: CGPoint(x: -200, y: -200), endPoint: CGPoint(x: 200, y: 200)) : .color(ring == "D" ? Td.fluo : Td.sunset))
                    } else if aim == key {
                        ctx.fill(p, with: .color(Td.ciel))
                    } else {
                        ctx.fill(p, with: .color(c))
                    }
                    ctx.stroke(p, with: .color(wire), lineWidth: 0.8)
                }
                let a = (Double(i) * 18 - 90) * .pi / 180
                let on = hits.contains { $0.hasPrefix("\(sec)") && !$0.hasPrefix("\(sec)0") && Int($0.dropLast()) == sec }
                ctx.draw(
                    Text("\(sec)").font(.tdRounded(on ? 21 : 18, .heavy)).foregroundColor(on ? Td.sunset : Color(hex: 0xD9D7D0)),
                    at: CGPoint(x: 186 * cos(a), y: 186 * sin(a))
                )
            }
            let ob = Path(ellipseIn: CGRect(x: -Self.rOb, y: -Self.rOb, width: 2 * Self.rOb, height: 2 * Self.rOb))
            let b = Path(ellipseIn: CGRect(x: -Self.rB, y: -Self.rB, width: 2 * Self.rB, height: 2 * Self.rB))
            ctx.fill(ob, with: .color(hits.contains("25O") ? Td.crepuscule : (aim == "25O" ? Td.ciel : (heat.contains(25) ? Td.sunset : Color(hex: 0x0C6A55)))))
            ctx.fill(b, with: .color(hits.contains("25B") ? Td.crepuscule : (aim == "25B" ? Td.ciel : (heat.contains(25) ? Td.sunset : Color(hex: 0xE8434F)))))
            ctx.stroke(ob, with: .color(wire), lineWidth: 0.8)
            ctx.stroke(b, with: .color(wire), lineWidth: 0.8)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static func seg(_ r0: Double, _ r1: Double, _ a0: Double, _ a1: Double) -> Path {
        func rad(_ d: Double) -> Angle { .degrees(d - 90) }
        var p = Path()
        p.addArc(center: .zero, radius: r1, startAngle: rad(a0), endAngle: rad(a1), clockwise: false)
        p.addArc(center: .zero, radius: r0, startAngle: rad(a1), endAngle: rad(a0), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Marque Cricket : /, X, puis X cerclé.
struct TVCricketMark: View {
    let n: Int
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 32
            ctx.scaleBy(x: s, y: s)
            var p = Path()
            if n >= 1 && n < 3 { p.move(to: CGPoint(x: 8, y: 24)); p.addLine(to: CGPoint(x: 24, y: 8)) }
            if n == 2 { p.move(to: CGPoint(x: 8, y: 8)); p.addLine(to: CGPoint(x: 24, y: 24)) }
            if n >= 3 {
                p.addEllipse(in: CGRect(x: 4, y: 4, width: 24, height: 24))
                p.move(to: CGPoint(x: 8.5, y: 23.5)); p.addLine(to: CGPoint(x: 23.5, y: 8.5))
                p.move(to: CGPoint(x: 8.5, y: 8.5)); p.addLine(to: CGPoint(x: 23.5, y: 23.5))
            }
            ctx.stroke(p, with: .color(n >= 3 ? Td.sunset : Td.ink), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        }
        .frame(width: 52, height: 52)
    }
}
