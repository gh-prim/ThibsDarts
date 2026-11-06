import PhotosUI
import SwiftUI

/// Racine du parcours d'installation.
struct SetupFlow: View {
    @StateObject private var model = SetupModel()

    var body: some View {
        Group {
            switch model.step {
            case .scan: ScanStep()
            case .wifi: WifiStep()
            case .password: PasswordStep()
            case .profile: ProfileStep()
            case .done: DoneStep()
            }
        }
        .transition(.opacity)
        .environmentObject(model)
        .onOpenURL { model.handle(url: $0) }
    }
}

/// Gabarit commun des planches iOS : NavBar, étapes, contenu. padding 54/16/40, gap 16.
private struct SetupPage<Content: View>: View {
    @EnvironmentObject var model: SetupModel
    var back = true
    var success = false
    var error = false
    let content: Content

    init(back: Bool = true, success: Bool = false, error: Bool = false, @ViewBuilder content: () -> Content) {
        self.back = back
        self.success = success
        self.error = error
        self.content = content()
    }

    var body: some View {
        Stage {
            VStack(spacing: Td.s4) {
                NavBar(title: "Installation", back: back ? "Retour" : nil) { model.back() }
                OnboardingProgress(steps: SetupModel.steps, current: model.progressIndex, success: success, error: error)
                content
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
            .padding(.bottom, Td.s2)
        }
    }
}

// MARK: ScanQR

private struct ScanStep: View {
    @EnvironmentObject var model: SetupModel
    @StateObject private var camera = Camera()
    @State private var manual = false

    var body: some View {
        SetupPage(back: false) {
            ZStack {
                if Camera.hasCamera && camera.available {
                    CameraPreview(session: camera.session)
                } else {
                    // Simulateur ou caméra refusée : le décor de la planche.
                    RadialGradient(
                        colors: [Color(hex: 0x3A3B42), Color(hex: 0x1E1F24), Color(hex: 0x0B0B0D)],
                        center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 420
                    )
                }
                ScanFrame()
                VStack {
                    if let f = model.found {
                        Badge(text: "ThibsDarts trouvé, code \(f.code)", tone: .succes, icon: .check)
                    } else if model.busy {
                        Badge(text: "Connexion au Pi...", tone: .info, icon: .loaderCircle)
                    }
                    Spacer()
                }
                .padding(Td.s4)
            }
            .frame(height: 420)
            .clipShape(RoundedRectangle(cornerRadius: Td.rXl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Td.rXl, style: .continuous).strokeBorder(Td.verreBord))

            VStack(spacing: Td.s1) {
                Text("Vise le QR code sur l’écran du Pi.").font(.td(17, .semibold))
                Text("Ton iPhone rejoint le Wi-Fi du Pi le temps du setup. iOS va te demander l’autorisation.")
                    .font(.td(13))
                    .foregroundStyle(Td.ink3)
            }
            .multilineTextAlignment(.center)

            if let e = model.error { Banner(text: e, error: true) }
            Spacer(minLength: 0)
            TdButton(title: "Taper le code à la main", variant: .tertiary, block: true) { manual = true }
        }
        .onAppear {
            camera.startScanning { code in
                if let url = URL(string: code) { model.handle(url: url) }
            }
        }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $manual) { ManualCode().environmentObject(model).presentationDetents([.height(320)]) }
    }
}

/// Coins orange en haut, rose en bas (236 x 236).
private struct ScanFrame: View {
    var body: some View {
        ZStack {
            corner(Td.sunset).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            corner(Td.sunset).scaleEffect(x: -1).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            corner(Td.crepuscule).scaleEffect(y: -1).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            corner(Td.crepuscule).scaleEffect(x: -1, y: -1).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: 236, height: 236)
        .accessibilityHidden(true)
    }

    private func corner(_ c: Color) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 2, y: 48))
            p.addLine(to: CGPoint(x: 2, y: 20))
            p.addArc(tangent1End: CGPoint(x: 2, y: 2), tangent2End: CGPoint(x: 20, y: 2), radius: 18)
            p.addLine(to: CGPoint(x: 48, y: 2))
        }
        .stroke(c, style: StrokeStyle(lineWidth: 4, lineCap: .butt))
        .frame(width: 48, height: 48)
    }
}

private struct ManualCode: View {
    @EnvironmentObject var model: SetupModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        Stage {
            VStack(alignment: .leading, spacing: Td.s4) {
                ObHeader(title: "Code d’appairage", detail: "Les 4 chiffres affichés sur l’écran du Pi.")
                Field(label: "Code", text: $code, placeholder: "4821", icon: .lock)
                    .keyboardType(.numberPad)
                TdButton(title: "Connecter", icon: .arrowRight, block: true, state: code.count == 4 ? .normal : .disabled) {
                    model.connect(SetupLink(code: code))
                    dismiss()
                }
                Spacer(minLength: 0)
            }
            .padding(Td.s4)
            .padding(.top, Td.s4)
        }
    }
}

// MARK: WifiQR

private struct WifiStep: View {
    @EnvironmentObject var model: SetupModel

    var body: some View {
        SetupPage {
            VStack(alignment: .leading, spacing: Td.s1) {
                Text("Le Wi-Fi de la maison").font(.td(22, .bold))
                Text("Le Pi 4 a vu ces réseaux. Choisis celui de la cible.").font(.td(15)).foregroundStyle(Td.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: Td.s4) {
                    ObHeader(title: "Quel Wi-Fi ?", detail: "Les 2 Pi vont dessus et discutent entre eux.")
                    picker
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            TdButton(
                title: "Continuer", icon: .arrowRight, block: true,
                state: model.selected == nil ? .disabled : .normal
            ) { model.chooseNetwork() }
        }
    }

    @ViewBuilder private var picker: some View {
        if model.networksLoading && model.networks.isEmpty {
            GlassList {
                ForEach(0..<3, id: \.self) { i in
                    HStack {
                        RoundedRectangle(cornerRadius: 4).fill(Td.verreMoyen).frame(width: 180, height: 16)
                        Spacer()
                    }
                    .padding(.horizontal, Td.s4)
                    .frame(minHeight: 52)
                    .overlay(alignment: .top) { if i > 0 { Td.bord.frame(height: 1) } }
                }
            }
        } else if model.networks.isEmpty {
            VStack(spacing: Td.s3) {
                Icon(name: .wifiOff, size: 24).foregroundStyle(Td.erreur)
                Text("Le Pi ne voit aucun réseau.").font(.td(15))
                TdButton(title: "Rescanner", variant: .secondary, size: .sm, icon: .refreshCw) { model.loadNetworks() }
            }
            .frame(maxWidth: .infinity)
            .padding(Td.s6)
        } else {
            GlassList {
                ForEach(Array(model.networks.enumerated()), id: \.element.id) { i, n in
                    let on = model.selected == n
                    Button { model.selected = n } label: {
                        HStack(spacing: Td.s3) {
                            Text(n.name).font(.td(17)).frame(maxWidth: .infinity, alignment: .leading)
                            if on { Icon(name: .check, size: 18).foregroundStyle(Td.sunset) }
                            if n.locked { Icon(name: .lock, size: 16).foregroundStyle(Td.ink2) }
                            SignalBars(level: n.signal)
                        }
                        .padding(.vertical, Td.s2)
                        .padding(.horizontal, Td.s4)
                        .frame(minHeight: 52)
                        .background(on ? Td.sunsetFond : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { if i > 0 { Td.bord.frame(height: 1) } }
                }
            }
        }
    }
}

// MARK: WifiMdpQR

private struct PasswordStep: View {
    @EnvironmentObject var model: SetupModel

    var body: some View {
        SetupPage(error: model.wifiState == .error) {
            VStack(alignment: .leading, spacing: Td.s4) {
                ObHeader(title: "Mot de passe de \(model.selected?.name ?? "ton Wi-Fi")")
                Field(
                    label: "Mot de passe", text: $model.password, hint: hint, icon: .lock,
                    secure: true, state: model.wifiState, contentType: .password
                )
                TdButton(title: buttonTitle, block: true, state: buttonState) { model.sendWifi() }
            }
            Spacer(minLength: 0)
            Text("Le Pi 4 se connecte, puis passe le Wi-Fi au Pi 5. Ton iPhone revient sur ton Wi-Fi tout seul.")
                .font(.td(13))
                .foregroundStyle(Td.ink3)
                .multilineTextAlignment(.center)
        }
    }

    private var hint: String {
        switch model.wifiState {
        case .error: "Mot de passe refusé. Ça arrive."
        case .success: "Connecté."
        case .loading: "Le Pi essaie..."
        case .normal: "Reste sur cet appareil et sur les Pi."
        }
    }

    private var buttonTitle: String {
        switch model.wifiState {
        case .loading: "Connexion"
        case .success: "Connecté"
        case .error: "Réessayer"
        case .normal: "Connecter"
        }
    }

    private var buttonState: ButtonState {
        switch model.wifiState {
        case .loading: .loading
        case .success: .success
        default: .normal
        }
    }
}

// MARK: ProfilQR

private struct ProfileStep: View {
    @EnvironmentObject var model: SetupModel
    @State private var shooting = false
    @State private var pick: PhotosPickerItem?

    var body: some View {
        SetupPage(back: false) {
            ScrollView {
                VStack(spacing: Td.s4) {
                    VStack(spacing: Td.s3) {
                        if let p = model.photo {
                            ProfileRing(image: p, size: 124, ring: 4, gap: 3)
                        } else {
                            Circle()
                                .strokeBorder(Td.bordControle, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                                .frame(width: 132, height: 132)
                                .overlay(Icon(name: .camera, size: 40).foregroundStyle(Td.ink3))
                        }
                        photoButton
                        Text("Une vraie photo, pas un avatar. Elle s’affiche sur le Pi et sur la TV.")
                            .font(.td(13))
                            .foregroundStyle(Td.ink3)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, Td.s1)

                    Field(label: "Prénom", text: $model.firstName, icon: .user, contentType: .givenName)
                    Field(label: "Nom", text: $model.lastName, placeholder: "Ton nom de famille", contentType: .familyName)
                    Field(
                        label: "Surnom sur l’écran", text: $model.nickname, placeholder: model.firstName,
                        hint: "Court, ça tient mieux sur la cible.", contentType: .nickname
                    )
                    if let e = model.error { Banner(text: e, error: true) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            TdButton(
                title: model.photo == nil ? "Ajoute ta photo pour continuer" : "Continuer",
                icon: .arrowRight, block: true,
                state: model.busy ? .loading : model.canFinish ? .normal : .disabled
            ) { model.finish() }
        }
        .fullScreenCover(isPresented: $shooting) { PhotoCapture().environmentObject(model) }
        .onChange(of: pick) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    model.photo = img
                }
            }
        }
    }

    @ViewBuilder private var photoButton: some View {
        let title = model.photo == nil ? "Prendre ma photo" : "Reprendre ma photo"
        if Camera.hasCamera {
            TdButton(title: title, size: .sm, icon: .camera) { shooting = true }
        } else {
            // Simulateur : pas de caméra, on prend une photo de la photothèque.
            PhotosPicker(selection: $pick, matching: .images) {
                HStack(spacing: Td.s2) {
                    Icon(name: .camera, size: 16)
                    Text(title).font(.td(13, .semibold))
                }
                .padding(.horizontal, Td.s3)
                .frame(height: 32)
                .foregroundStyle(Td.onAccent)
                .background(RoundedRectangle(cornerRadius: Td.rSm).fill(Td.goldenHour))
            }
        }
    }
}

// MARK: PhotoQR

private struct PhotoCapture: View {
    @EnvironmentObject var model: SetupModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = Camera()

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: 380)
            ZStack {
                Td.beton
                CameraPreview(session: camera.session)
                // Voile sombre avec un trou rond de 280.
                Rectangle()
                    .fill(Color(hex: 0x08080A, alpha: 0.72))
                    .reverseMask {
                        Circle().frame(width: 280, height: 280).position(center)
                    }
                Circle()
                    .strokeBorder(Td.sunset, lineWidth: 3)
                    .frame(width: 280, height: 280)
                    .shadow(color: Td.sunset.opacity(0.45), radius: 16)
                    .position(center)

                VStack(spacing: 6) {
                    Text("Ta tête dans le rond.").font(.td(22, .bold))
                    Text("Bonne lumière, pas de lunettes de soleil.").font(.td(15)).foregroundStyle(Td.ink2)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, Td.s6)
                .position(x: geo.size.width / 2, y: 64 + 31)

                HStack {
                    TdButton(title: "Annuler", variant: .tertiary) { dismiss() }
                    Spacer()
                    Button {
                        camera.capture { img in
                            if let img { model.photo = img }
                            dismiss()
                        }
                    } label: {
                        Circle()
                            .fill(Td.ink)
                            .padding(8)
                            .frame(width: 80, height: 80)
                            .overlay(Circle().strokeBorder(Td.ink, lineWidth: 4))
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel("Prendre la photo")
                    Spacer()
                    IconButton(icon: .refreshCw, label: "Changer de caméra") { camera.flip() }
                }
                .padding(.horizontal, Td.s8)
                .position(x: geo.size.width / 2, y: geo.size.height - 56 - 40)
            }
            .foregroundStyle(Td.ink)
        }
        .ignoresSafeArea()
        .onAppear { camera.startSelfie() }
        .onDisappear { camera.stop() }
    }
}

private extension View {
    func reverseMask<M: View>(@ViewBuilder _ mask: () -> M) -> some View {
        self.mask {
            Rectangle().overlay { mask().blendMode(.destinationOut) }.compositingGroup()
        }
    }
}

// MARK: FiniQR

private struct DoneStep: View {
    @EnvironmentObject var model: SetupModel
    @State private var showHome = false

    var body: some View {
        SetupPage(back: false, success: true) {
            VStack(spacing: Td.s3) {
                ProfileRing(image: model.photo, size: 120, ring: 4, gap: 3)
                Text("C’est prêt, \(model.firstName).").font(.td(28, .heavy))
                Text("Regarde l’écran du Pi, il te dit bonjour.").font(.td(15)).foregroundStyle(Td.ink2)
            }
            .multilineTextAlignment(.center)
            .padding(.top, Td.s4)

            // Le Pi 5 sera relié par MQTT dans une prochaine étape.
            PiConnection(pi4: .ok, pi5: .busy)
            Spacer(minLength: 0)
            TdButton(title: "Aller jouer", icon: .play, block: true) { showHome = true }
        }
        .alert("Bientôt", isPresented: $showHome) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("L’accueil de l’app arrive à la prochaine étape.")
        }
    }
}
