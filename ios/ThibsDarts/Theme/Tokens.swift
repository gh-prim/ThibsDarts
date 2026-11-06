import SwiftUI

/// Tokens du design system ThibsDarts "Golden Hour Urbex" (tokens.css de Claude Design).
enum Td {
    // Couleurs
    static let beton = Color(hex: 0x121214)
    static let betonNuit = Color(hex: 0x0B0B0D)
    static let asphalte = Color(hex: 0x1E1F24)
    static let asphalteHaut = Color(hex: 0x2A2B31)
    static let sunset = Color(hex: 0xFF7A2F)
    static let crepuscule = Color(hex: 0xFF4D8D)
    static let ciel = Color(hex: 0x4FA3FF)
    static let fluo = Color(hex: 0xFFE14D)
    static let onAccent = Color(hex: 0x121214)
    static let ink = Color(hex: 0xF5F3EE)
    static let ink2 = Color(hex: 0xB9B9C2)
    static let ink3 = Color(hex: 0x94959F)
    static let succes = Color(hex: 0x3DDC97)
    static let succesFond = Color(hex: 0x3DDC97, alpha: 0.14)
    static let erreur = Color(hex: 0xFF6464)
    static let erreurFond = Color(hex: 0xFF6464, alpha: 0.14)
    static let infoFond = Color(hex: 0x4FA3FF, alpha: 0.14)
    static let sunsetFond = Color(hex: 0xFF7A2F, alpha: 0.16)
    static let desactiveFond = Color.white.opacity(0.05)
    static let desactiveInk = Color(hex: 0x6C6D76)
    static let bord = Color.white.opacity(0.10)
    static let bordControle = Color(hex: 0x6F707A)
    static let verreLeger = Color.white.opacity(0.05)
    static let verreMoyen = Color.white.opacity(0.09)
    static let verreBord = Color.white.opacity(0.16)
    static let verreReflet = Color.white.opacity(0.22)

    static let goldenHour = LinearGradient(
        colors: [sunset, crepuscule],
        startPoint: UnitPoint(x: 0.05, y: 0.25),
        endPoint: UnitPoint(x: 0.95, y: 0.75)
    )

    // Espacements
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16
    static let s5: CGFloat = 20, s6: CGFloat = 24, s8: CGFloat = 32

    // Rayons
    static let rXs: CGFloat = 6, rSm: CGFloat = 10, rMd: CGFloat = 14, rLg: CGFloat = 20, rXl: CGFloat = 28

    static let sortie = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Typo : SF Pro sur Apple (text, display, rounded pour les chiffres).
extension Font {
    static func td(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func tdRounded(_ size: CGFloat, _ weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Icônes Lucide (même jeu que le design system), via la police lucide.ttf.
enum LucideIcon: UInt32 {
    case chevronLeft = 57454
    case check = 57452
    case loaderCircle = 57610
    case camera = 57444
    case lock = 57611
    case eye = 57530
    case eyeOff = 57531
    case arrowRight = 57417
    case play = 57660
    case refreshCw = 57669
    case circleAlert = 57463
    case info = 57593
    case wifi = 57774
    case wifiOff = 57775
    case user = 57759
    case target = 57728
    case chartLine = 58021
    case history = 57845
    case plus = 57661
    case search = 57681
    case bell = 57433
    case chevronRight = 57455
    case cpu = 57513

    var glyph: String { String(UnicodeScalar(rawValue).map(Character.init) ?? " ") }
}

struct Icon: View {
    let name: LucideIcon
    var size: CGFloat = 20

    var body: some View {
        if name == .loaderCircle {
            Spinner(size: size)
        } else {
            Text(name.glyph)
                .font(.custom("lucide", fixedSize: size))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// loader-circle qui tourne.
struct Spinner: View {
    var size: CGFloat = 20
    @State private var turn = false

    var body: some View {
        Text(LucideIcon.loaderCircle.glyph)
            .font(.custom("lucide", fixedSize: size))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turn ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turn = true }
            }
            .accessibilityLabel("Chargement")
    }
}
