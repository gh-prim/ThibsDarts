import PhotosUI
import SwiftUI

/// Premier lancement : Bienvenue, trouver la cible, choisir son profil et taper son code.
/// Ou installer sa cible (le propriétaire devient le premier profil).
struct OnboardingFlow: View {
    enum Step: Equatable { case welcome, find, who(URL), newProfile(URL), newPin(URL), photo, install }

    @EnvironmentObject var app: AppModel
    @State private var step: Step = .welcome

    var body: some View {
        Group {
            switch step {
            case .welcome: WelcomeView(onJoin: { go(.find) }, onInstall: { go(.install) })
            case .find: CibleFinder(onBack: { go(.welcome) }, onFound: { go(.who($0)) })
            case let .who(base): WhoView(base: base, onBack: { go(.welcome) }, onNew: { go(.newProfile(base)) })
            case let .newProfile(base):
                ProfileView(onBack: { go(.who(base)) }, onDone: { go(.newPin(base)) })
            case let .newPin(base): NewProfilePinView(base: base, onBack: { go(.newProfile(base)) })
            case .photo:
                // Connecté à un profil sans photo (pote ajouté par le propriétaire) : on la prend.
                ProfileView(onBack: nil, onDone: {})
            case .install: SetupFlow(onExit: { go(.welcome) })
            }
        }
        .transition(.opacity)
        .onAppear { if app.signedIn && !app.hasProfile { step = .photo } }
        .onChange(of: app.signedIn) { _, inside in
            if inside && !app.hasProfile { go(.photo) }
        }
    }

    private func go(_ s: Step) {
        withAnimation(Td.sortie) { step = s }
    }
}

// MARK: Main "Bienvenue"

private struct WelcomeView: View {
    let onJoin: () -> Void
    let onInstall: () -> Void

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
                VStack(spacing: Td.s2) {
                    TdButton(title: "C’est parti", icon: .arrowRight, block: true, action: onJoin)
                    TdButton(title: "Installer ma cible", variant: .tertiary, icon: .cpu, block: true, action: onInstall)
                }
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
    @State private var confirmLogout = false
    @State private var addFriend = false
    @State private var busy = false
    @State private var error: String?

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
                        if let error { Banner(text: error, error: true) }
                        if onBack == nil {
                            if app.isOwner && app.hasProfile {
                                TdButton(title: "Ajouter un pote sans appli", variant: .secondary, icon: .plus, block: true) {
                                    addFriend = true
                                }
                                .padding(.top, Td.s2)
                            }
                            TdButton(title: "Se déconnecter", variant: .tertiary, icon: .logOut, block: true) {
                                confirmLogout = true
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                TdButton(
                    title: photo == nil ? "Ajoute ta photo pour continuer" : "Continuer",
                    icon: .arrowRight, block: true,
                    state: busy ? .loading
                        : (photo != nil && !nickname.trimmingCharacters(in: .whitespaces).isEmpty ? .normal : .disabled)
                ) { save() }
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
        .sheet(isPresented: $addFriend) { AddFriendView().environmentObject(app) }
        .confirmationDialog("Se déconnecter ?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { app.logout() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ton profil et tes parties restent sur la cible. Pour revenir, il te faudra ton code.")
        }
        .onChange(of: pick) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    photo = img
                }
            }
        }
    }

    /// Connecté à un profil : le surnom et la photo partent aussi sur la cible.
    private func save() {
        let old = (app.nickname, app.photo)
        app.saveProfile(nickname: nickname, photo: photo)
        guard app.signedIn else { return onDone() }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await LobbyAPI.syncProfile(app: app)
                onDone()
            } catch {
                app.saveProfile(nickname: old.0, photo: old.1)
                self.error = error.localizedDescription
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
