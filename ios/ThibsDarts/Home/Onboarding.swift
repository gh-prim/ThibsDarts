import PhotosUI
import SwiftUI

/// Premier lancement d'un joueur : Bienvenue, Ton profil, Rejoindre ou installer.
struct OnboardingFlow: View {
    enum Step { case welcome, profile, choice, install, join }

    @EnvironmentObject var app: AppModel
    @State private var step: Step = .welcome

    var body: some View {
        Group {
            switch step {
            case .welcome: WelcomeView { go(.profile) }
            case .profile: ProfileView(onBack: { go(.welcome) }, onDone: { go(.choice) })
            case .choice: ChoiceView(onBack: { go(.profile) }, onJoin: { go(.join) }, onInstall: { go(.install) })
            case .install: SetupFlow(onExit: { go(.choice) })
            case .join: JoinView(onBack: { go(.choice) })
            }
        }
        .transition(.opacity)
    }

    private func go(_ s: Step) {
        withAnimation(Td.sortie) { step = s }
    }
}

// MARK: Main "Bienvenue"

private struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        Stage {
            VStack(spacing: Td.s6) {
                VStack(spacing: Td.s6) {
                    LogoView(height: 64)
                    Text("La cible compte.\nToi, tu lances.")
                        .font(.td(34, .heavy))
                        .tracking(-0.5)
                    Text("Rejoins les parties de tes potes, reçois une alerte quand c’est ton tour et garde toutes tes stats.")
                        .font(.td(17))
                        .foregroundStyle(Td.ink2)
                }
                .multilineTextAlignment(.center)
                .frame(maxHeight: .infinity)
                TdButton(title: "Créer mon profil", icon: .arrowRight, block: true, action: onStart)
            }
            .padding(.horizontal, Td.s6)
            .padding(.top, Td.s4)
            .padding(.bottom, Td.s5)
        }
    }
}

// MARK: Profil "Ton profil"

struct ProfileView: View {
    var title = "Ton profil"
    let onBack: (() -> Void)?
    let onDone: () -> Void

    @EnvironmentObject var app: AppModel
    @State private var nickname = ""
    @State private var photo: UIImage?
    @State private var shooting = false
    @State private var pick: PhotosPickerItem?

    var body: some View {
        Stage {
            VStack(spacing: Td.s4) {
                NavBar(title: title, back: onBack == nil ? nil : "Retour") { onBack?() }
                ScrollView {
                    VStack(spacing: Td.s4) {
                        VStack(spacing: Td.s3) {
                            if photo != nil || !nickname.isEmpty {
                                Avatar(name: nickname, image: photo, size: 128)
                            } else {
                                Circle()
                                    .strokeBorder(Td.bordControle, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                                    .frame(width: 128, height: 128)
                                    .overlay(Icon(name: .camera, size: 40).foregroundStyle(Td.ink3))
                            }
                            photoButton
                        }
                        .padding(.vertical, Td.s2)
                        Field(
                            label: "Ton surnom", text: $nickname, placeholder: "Thibs",
                            hint: "C’est ce que les autres voient sur l’écran du Pi.", icon: .user,
                            contentType: .nickname
                        )
                        TdToggle(
                            label: "Me prévenir quand c’est mon tour",
                            hint: "Une notification par tour. Rien d’autre.",
                            isOn: $app.notify
                        )
                        .padding(Td.s4)
                        .background(RoundedRectangle(cornerRadius: Td.rLg).fill(Td.verreLeger))
                        .overlay(RoundedRectangle(cornerRadius: Td.rLg).strokeBorder(Td.verreBord))
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                TdButton(
                    title: photo == nil ? "Ajoute ta photo pour continuer" : "Continuer",
                    icon: .arrowRight, block: true,
                    state: photo != nil && !nickname.trimmingCharacters(in: .whitespaces).isEmpty ? .normal : .disabled
                ) {
                    app.saveProfile(nickname: nickname, photo: photo)
                    onDone()
                }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
            .padding(.bottom, Td.s2)
        }
        .onAppear {
            nickname = app.nickname
            photo = app.photo
        }
        .fullScreenCover(isPresented: $shooting) { PhotoCapture { photo = $0 } }
        .onChange(of: pick) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    photo = img
                }
            }
        }
    }

    @ViewBuilder private var photoButton: some View {
        let label = photo == nil ? "Prendre ma photo" : "Changer la photo"
        if Camera.hasCamera {
            TdButton(title: label, variant: .secondary, size: .sm, icon: .camera) { shooting = true }
        } else {
            PhotosPicker(selection: $pick, matching: .images) {
                HStack(spacing: Td.s2) {
                    Icon(name: .camera, size: 16)
                    Text(label).font(.td(13, .semibold))
                }
                .padding(.horizontal, Td.s3)
                .frame(height: 32)
                .foregroundStyle(Td.ink)
                .background(RoundedRectangle(cornerRadius: Td.rSm).fill(Td.verreMoyen))
                .overlay(RoundedRectangle(cornerRadius: Td.rSm).strokeBorder(Td.verreBord))
            }
        }
    }
}

// MARK: Choix "T'es là pour quoi ?"

private struct ChoiceView: View {
    let onBack: () -> Void
    let onJoin: () -> Void
    let onInstall: () -> Void

    var body: some View {
        Stage {
            VStack(alignment: .leading, spacing: Td.s4) {
                NavBar(title: "", back: "Profil", onBack: onBack)
                VStack(alignment: .leading, spacing: Td.s1) {
                    Text("T’es là pour quoi ?").font(.td(34, .heavy)).tracking(-0.5)
                    Text("Tu pourras changer d’avis plus tard.").font(.td(17)).foregroundStyle(Td.ink2)
                }
                card(
                    icon: .target, tint: Td.sunset, title: "Rejoindre une partie",
                    detail: "Tu es chez un pote. Scanne le QR code sur l’écran du Pi et c’est parti.",
                    accent: true, action: onJoin
                )
                card(
                    icon: .cpu, tint: Td.ink2, title: "Installer ma cible",
                    detail: "Tu as les 2 Pi et les caméras. On les connecte au Wi-Fi, une seule fois.",
                    accent: false, action: onInstall
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
        }
    }

    private func card(
        icon: LucideIcon, tint: Color, title: String, detail: String, accent: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Icon(name: icon, size: 32).foregroundStyle(tint)
                Text(title).font(.td(22, .bold))
                Text(detail).font(.td(15)).foregroundStyle(Td.ink2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Td.s5)
            .background(RoundedRectangle(cornerRadius: Td.rXl).fill(accent ? Td.sunset.opacity(0.12) : Td.verreLeger))
            .overlay(
                RoundedRectangle(cornerRadius: Td.rXl)
                    .strokeBorder(accent ? Td.sunset.opacity(0.6) : Td.verreBord)
            )
            .shadow(color: accent ? Td.sunset.opacity(0.25) : .clear, radius: 16)
        }
        .buttonStyle(PressScale())
        .foregroundStyle(Td.ink)
    }
}
