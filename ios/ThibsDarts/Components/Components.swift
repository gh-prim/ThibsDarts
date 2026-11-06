import SwiftUI

// Composants du design system ThibsDarts, version iOS (classe .ios des planches).

/// Fond béton avec la lueur "horizon" (td-stage--horizon).
struct Stage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Td.beton.ignoresSafeArea()
            GeometryReader { geo in
                // CSS : radial-gradient(120% 70% at 50% 118%, ...) ; l'ellipse fait 2,4 L sur 1,4 H.
                EllipticalGradient(
                    stops: [
                        .init(color: Td.sunset.opacity(0.30), location: 0),
                        .init(color: Td.crepuscule.opacity(0.14), location: 0.45),
                        .init(color: Td.beton.opacity(0), location: 0.75),
                    ],
                    center: .center,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5
                )
                .frame(width: geo.size.width * 2.4, height: geo.size.height * 1.4)
                .position(x: geo.size.width / 2, y: geo.size.height * 1.18)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            content
        }
        .foregroundStyle(Td.ink)
    }
}

/// Barre de navigation (NavBar).
struct NavBar: View {
    let title: String
    var back: String?
    var onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: Td.s2) {
            if let back {
                IconButton(icon: .chevronLeft, label: back) { onBack?() }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Text(title)
                .font(.td(17, .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: 44, height: 44)
        }
        .frame(minHeight: 44)
        .padding(.vertical, Td.s1)
        .padding(.horizontal, Td.s3)
    }
}

/// Étapes d'installation (OnboardingProgress).
struct OnboardingProgress: View {
    let steps: [String]
    var current: Int = 0
    var success = false
    var error = false

    var body: some View {
        VStack(alignment: .leading, spacing: Td.s2) {
            HStack(spacing: Td.s1) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, _ in
                    segment(i)
                        .frame(height: 5)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            HStack {
                Text(success ? "Tout est prêt" : error ? "\(steps[current]): à refaire" : steps[current])
                    .font(.td(13, .semibold))
                    .foregroundStyle(Td.ink)
                Spacer()
                Text("\(current + 1) sur \(steps.count)")
                    .font(.td(13))
                    .monospacedDigit()
                    .foregroundStyle(Td.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func segment(_ i: Int) -> some View {
        if success {
            Td.succes
        } else if i < current {
            Td.ink
        } else if i == current {
            if error { Td.erreur } else { Rectangle().fill(Td.goldenHour) }
        } else {
            Td.verreMoyen
        }
    }
}

enum ButtonVariant { case primary, secondary, tertiary }
enum ButtonSize { case md, sm }
enum ButtonState { case normal, loading, success, disabled }

/// Bouton du design system (Button).
struct TdButton: View {
    let title: String
    var variant: ButtonVariant = .primary
    var size: ButtonSize = .md
    var icon: LucideIcon?
    var block = false
    var state: ButtonState = .normal
    let action: () -> Void

    private var height: CGFloat { size == .sm ? 32 : 44 }
    private var fontSize: CGFloat { size == .sm ? 13 : 17 }
    private var radius: CGFloat { size == .sm ? Td.rSm : Td.rMd }

    var body: some View {
        Button(action: { if state == .normal { action() } }) {
            HStack(spacing: Td.s2) {
                switch state {
                case .loading: Spinner(size: size == .sm ? 16 : 20)
                case .success: Icon(name: .check, size: size == .sm ? 16 : 20)
                default: if let icon { Icon(name: icon, size: size == .sm ? 16 : 20) }
                }
                Text(title).font(.td(fontSize, .semibold)).lineLimit(1)
            }
            .padding(.horizontal, variant == .tertiary || size == .sm ? Td.s3 : Td.s5)
            .frame(height: height)
            .frame(maxWidth: block ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if variant == .secondary && state != .disabled {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Td.verreBord)
                }
            }
            .shadow(color: glow, radius: 16)
        }
        .buttonStyle(PressScale())
        .disabled(state == .disabled)
    }

    private var foreground: Color {
        if state == .disabled { return Td.desactiveInk }
        if state == .success { return Td.onAccent }
        return switch variant {
        case .primary: Td.onAccent
        case .secondary: Td.ink
        case .tertiary: Td.sunset
        }
    }

    @ViewBuilder private var background: some View {
        if state == .disabled {
            Td.desactiveFond
        } else if state == .success {
            Td.succes
        } else {
            switch variant {
            case .primary: Rectangle().fill(Td.goldenHour)
            case .secondary: Td.verreMoyen
            case .tertiary: Color.clear
            }
        }
    }

    private var glow: Color {
        variant == .primary && state == .normal ? Td.sunset.opacity(0.45) : .clear
    }
}

/// Bouton rond en verre, icône seule.
struct IconButton: View {
    let icon: LucideIcon
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(name: icon, size: 20)
                .frame(width: 44, height: 44)
                .foregroundStyle(Td.ink)
                .background(Circle().fill(Td.verreMoyen))
                .overlay(Circle().strokeBorder(Td.verreBord))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.1), value: configuration.isPressed)
    }
}

enum BadgeTone { case neutre, succes, erreur, info, sunset }

/// Pastille courte (Badge).
struct Badge: View {
    let text: String
    var tone: BadgeTone = .neutre
    var icon: LucideIcon?

    var body: some View {
        HStack(spacing: Td.s1) {
            if let icon { Icon(name: icon, size: 12) }
            Text(text).font(.td(12, .semibold)).lineLimit(1)
        }
        .padding(.horizontal, Td.s2)
        .frame(height: 22)
        .foregroundStyle(fg)
        .background(RoundedRectangle(cornerRadius: Td.rXs).fill(bg))
    }

    private var fg: Color {
        switch tone {
        case .neutre: Td.ink2
        case .succes: Td.succes
        case .erreur: Td.erreur
        case .info: Td.ciel
        case .sunset: Td.sunset
        }
    }

    private var bg: Color {
        switch tone {
        case .neutre: Td.verreMoyen
        case .succes: Td.succesFond
        case .erreur: Td.erreurFond
        case .info: Td.infoFond
        case .sunset: Td.sunsetFond
        }
    }
}

enum FieldState { case normal, loading, success, error }

/// Champ de saisie (Field).
struct Field: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var hint: String?
    var icon: LucideIcon?
    var secure = false
    var state: FieldState = .normal
    var contentType: UITextContentType?

    @FocusState private var focused: Bool
    @State private var reveal = false

    init(
        label: String, text: Binding<String>, placeholder: String = "", hint: String? = nil,
        icon: LucideIcon? = nil, secure: Bool = false, state: FieldState = .normal,
        contentType: UITextContentType? = nil
    ) {
        self.label = label
        _text = text
        self.placeholder = placeholder
        self.hint = hint
        self.icon = icon
        self.secure = secure
        self.state = state
        self.contentType = contentType
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Td.s1) {
            Text(label).font(.td(13, .medium)).foregroundStyle(Td.ink2)
            HStack(spacing: Td.s2) {
                if let icon { Icon(name: icon, size: 20).foregroundStyle(Td.ink) }
                Group {
                    if secure && !reveal {
                        SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Td.ink3))
                    } else {
                        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Td.ink3))
                    }
                }
                .font(.td(17))
                .foregroundStyle(Td.ink)
                .textContentType(contentType)
                .autocorrectionDisabled(secure)
                .textInputAutocapitalization(secure ? .never : .words)
                .focused($focused)
                if state == .loading {
                    Spinner(size: 20).foregroundStyle(Td.ink)
                } else if secure {
                    Button { reveal.toggle() } label: {
                        Icon(name: reveal ? .eyeOff : .eye, size: 20).foregroundStyle(Td.ink3)
                    }
                    .accessibilityLabel(reveal ? "Masquer le mot de passe" : "Afficher le mot de passe")
                }
            }
            .padding(.horizontal, Td.s3)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Td.rSm).fill(Td.verreLeger))
            .overlay {
                RoundedRectangle(cornerRadius: Td.rSm).strokeBorder(borderColor, lineWidth: focused ? 2 : 1)
            }
            if let hint {
                HStack(spacing: Td.s1) {
                    if state == .error { Icon(name: .circleAlert, size: 14) }
                    if state == .success { Icon(name: .check, size: 14) }
                    Text(hint).font(.td(13))
                }
                .foregroundStyle(hintColor)
            }
        }
    }

    private var borderColor: Color {
        if focused { return Td.sunset }
        return switch state {
        case .error: Td.erreur
        case .success: Td.succes
        default: Td.bordControle
        }
    }

    private var hintColor: Color {
        switch state {
        case .error: Td.erreur
        case .success: Td.succes
        case .loading: Td.ciel
        case .normal: Td.ink3
        }
    }
}

/// Bandeau d'info ou d'erreur (Banner).
struct Banner: View {
    let text: String
    var error = false

    var body: some View {
        HStack(spacing: Td.s3) {
            Icon(name: error ? .circleAlert : .info, size: 20).foregroundStyle(error ? Td.erreur : Td.ciel)
            Text(text).font(.td(15)).foregroundStyle(Td.ink).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Td.s3)
        .padding(.horizontal, Td.s4)
        .background(RoundedRectangle(cornerRadius: Td.rMd).fill(error ? Td.erreurFond : Td.infoFond))
    }
}

/// Liste en verre (td-list).
struct GlassList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Td.verreLeger)
            .clipShape(RoundedRectangle(cornerRadius: Td.rLg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Td.rLg, style: .continuous).strokeBorder(Td.verreBord))
    }
}

/// Force du signal Wi-Fi, 4 barres (Sig).
struct SignalBars: View {
    let level: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? Td.ink : Td.bordControle)
                    .frame(width: 3, height: CGFloat(5 + 3 * i))
            }
        }
        .frame(height: 14, alignment: .bottom)
        .accessibilityLabel("Signal \(level) sur 4")
    }
}

/// Titre de bloc d'onboarding (td-ob__t et td-ob__d).
struct ObHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.td(28, .bold)).tracking(-0.3)
            if let detail {
                Text(detail).font(.td(15)).foregroundStyle(Td.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum PiStatus { case ok, busy, err }

/// Carte d'un Pi (PiCard) et bloc PiConnection.
struct PiConnection: View {
    var pi4: PiStatus = .ok
    var pi5: PiStatus = .ok

    var body: some View {
        let all = pi4 == .ok && pi5 == .ok
        let err = pi4 == .err || pi5 == .err
        VStack(alignment: .leading, spacing: Td.s4) {
            ObHeader(
                title: all ? "Tout est branché" : err ? "Un Pi fait la tête" : "On connecte tout ça",
                detail: all ? "T'as fait le minimum. C'est parfait." : err ? "Rapproche-le du Wi-Fi et relance." : "Ça prend moins de temps qu'une bière."
            )
            HStack(spacing: Td.s3) {
                PiCard(name: "Pi 4", role: "Écran joueur", status: pi4)
                PiCard(name: "Pi 5", role: "3 caméras", status: pi5)
            }
        }
    }
}

struct PiCard: View {
    let name: String
    let role: String
    let status: PiStatus

    var body: some View {
        VStack(alignment: .leading, spacing: Td.s2) {
            Group {
                switch status {
                case .ok: Icon(name: .check, size: 28).foregroundStyle(Td.succes)
                case .busy: Spinner(size: 28).foregroundStyle(Td.ciel)
                case .err: Icon(name: .circleAlert, size: 28).foregroundStyle(Td.erreur)
                }
            }
            Text(name).font(.td(15, .semibold))
            Text(role).font(.td(13)).foregroundStyle(Td.ink2)
            switch status {
            case .ok: Badge(text: "En ligne", tone: .succes)
            case .busy: Badge(text: "Connexion...", tone: .info)
            case .err: Badge(text: "Échec", tone: .erreur)
            }
        }
        .padding(Td.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.verreLeger))
        .overlay {
            RoundedRectangle(cornerRadius: Td.rLg)
                .strokeBorder(status == .ok ? Td.succes : status == .err ? Td.erreur : Td.verreBord)
        }
    }
}

/// Photo de profil ronde avec l'anneau Golden Hour.
struct ProfileRing: View {
    let image: UIImage?
    var size: CGFloat = 120
    var ring: CGFloat = 4
    var gap: CGFloat = 3

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Td.asphalteHaut
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Td.beton, lineWidth: gap))
        .padding(ring)
        .background(Circle().fill(Td.goldenHour))
        .shadow(color: Td.crepuscule.opacity(0.45), radius: 16)
    }
}

/// Logo ThibsDarts complet (SVG du design system dans le catalogue d'images).
struct LogoView: View {
    var height: CGFloat = 48

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("ThibsDarts")
    }
}
