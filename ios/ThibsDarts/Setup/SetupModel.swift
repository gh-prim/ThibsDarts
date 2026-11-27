import SwiftUI
import UIKit

/// Parcours d'installation du premier allumage (planches "5. Premier allumage par QR code").
@MainActor
final class SetupModel: ObservableObject {
    enum Step: Equatable { case scan, wifi, password, profile, pin, done }

    static let steps = ["Scanner", "Wi-Fi", "Profil"]

    @Published var step: Step = .scan
    @Published var found: SetupLink?
    @Published var busy = false
    @Published var error: String?

    @Published var networks: [WifiNetwork] = []
    @Published var networksLoading = false
    @Published var selected: WifiNetwork?
    @Published var password = ""
    @Published var wifiState: FieldState = .normal
    /// Texte sous le mot de passe pendant que l'iPhone cherche le Pi sur le Wi-Fi de la maison.
    @Published var wifiHint: String?

    @Published var firstName = ""
    @Published var lastName = ""
    @Published var nickname = ""
    @Published var photo: UIImage?

    let client = PiClient()
    var onExit: () -> Void = {}
    private var link: SetupLink?

    var progressIndex: Int {
        switch step {
        case .scan: 0
        case .wifi, .password: 1
        case .profile, .pin, .done: 2
        }
    }

    // MARK: Étape 1 : QR code ou code tapé

    func handle(url: URL) {
        guard let l = SetupLink(url: url) else { return }
        connect(l)
    }

    func connect(_ l: SetupLink) {
        guard !busy else { return }
        link = l
        found = l
        error = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                if let ssid = l.ssid { _ = await client.joinHotspot(ssid: ssid, key: l.key) }
                let url = try await client.locate(preferred: l.host, port: l.port)
                try await client.pair(at: url, code: l.code, device: UIDevice.current.name)
                try? await Task.sleep(for: .milliseconds(600))
                // Setup interrompu après le Wi-Fi (app fermée, Pi redémarré, iPhone resté sur le hotspot) : on reprend.
                if let s = try? await client.status() {
                    if s.phase == "profile" {
                        withAnimation(Td.sortie) { step = .profile }
                        return
                    }
                    if s.phase == "wifiConnecting" {
                        if let name = s.ssid { selected = WifiNetwork(name: name, signal: 4, locked: true) }
                        wifiState = .loading
                        withAnimation(Td.sortie) { step = .password }
                        Task { try? await waitForWifi() }
                        return
                    }
                }
                withAnimation(Td.sortie) { step = .wifi }
                loadNetworks()
            } catch {
                found = nil
                if let ssid = l.ssid, isUnreachable(error) {
                    let pass = l.key.map { " (mot de passe : \($0))" } ?? ""
                    self.error = "Rejoins le Wi-Fi \(ssid)\(pass) dans Réglages, puis rescanne."
                } else {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func isUnreachable(_ e: Error) -> Bool {
        if case .unreachable = e as? PiError { return true }
        return false
    }

    // MARK: Étape 2 : Wi-Fi de la maison

    func loadNetworks() {
        networksLoading = true
        Task {
            defer { networksLoading = false }
            do {
                networks = try await client.networks()
                if selected == nil { selected = networks.first }
            } catch {
                networks = []
            }
        }
    }

    func chooseNetwork() {
        guard selected != nil else { return }
        password = ""
        wifiState = .normal
        withAnimation(Td.sortie) { step = .password }
    }

    func sendWifi() {
        guard let net = selected else { return }
        wifiState = .loading
        wifiHint = nil
        error = nil
        Task {
            do {
                try await client.sendWifi(ssid: net.name, password: password)
                try await waitForWifi()
            } catch {
                wifiState = .error
            }
        }
    }

    /// Le Pi coupe son hotspot pour rejoindre la maison : l'iPhone revient sur son Wi-Fi
    /// et retrouve le Pi (dernière adresse, dartos-hub.local, Bonjour, puis tout le réseau).
    /// Le Pi peut aussi redémarrer pour une mise à jour : on attend, il reprend au profil.
    private func waitForWifi() async throws {
        let start = Date()
        let deadline = start.addingTimeInterval(240)
        var leftHotspot = false
        var rejoinedHotspot = false
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(1500))
            do {
                let s = try await client.status()
                if s.wifi == "ok" || s.phase == "profile" {
                    wifiHint = nil
                    wifiState = .success
                    try? await Task.sleep(for: .milliseconds(900))
                    withAnimation(Td.sortie) { step = .profile }
                    return
                }
                // Le Pi n'a pas pu rejoindre la maison : il a rouvert son hotspot.
                if s.wifi == "error" || (leftHotspot && (s.phase == "waiting" || s.phase == "paired")) {
                    wifiHint = nil
                    wifiState = .error
                    return
                }
            } catch PiError.http(401, _) {
                // Pi redémarré sans sa session : on se réappaire avec le code du QR.
                try? await repair()
            } catch {
                if !leftHotspot, let ssid = link?.ssid {
                    leftHotspot = true
                    client.leaveHotspot(ssid: ssid)
                    try? await Task.sleep(for: .seconds(4))
                }
                wifiHint = "On cherche le Pi sur ton Wi-Fi..."
                if (try? await client.relocate(port: link?.port ?? 8420)) != nil { continue }
                // Toujours rien après 75 s : le Wi-Fi a peut-être raté et le Pi a rouvert son hotspot.
                if !rejoinedHotspot, Date().timeIntervalSince(start) > 75, let ssid = link?.ssid {
                    rejoinedHotspot = true
                    if await client.joinHotspot(ssid: ssid, key: link?.key) {
                        try? await Task.sleep(for: .seconds(3))
                        _ = try? await client.relocate(port: link?.port ?? 8420)
                    }
                }
            }
        }
        wifiHint = "Pi introuvable. Mets ton iPhone sur le Wi-Fi de la maison et rescanne le QR du Pi."
        wifiState = .error
    }

    /// Nouvelle session avec le même code (le Pi le garde même s'il redémarre).
    private func repair() async throws {
        guard let code = link?.code, let base = client.base else { return }
        try await client.pair(at: base, code: code, device: UIDevice.current.name)
    }

    // MARK: Étape 3 : profil et photo

    var canFinish: Bool {
        photo != nil && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Clé du profil du propriétaire, donnée par le Pi à la fin du setup.
    var ownerKey: String?

    /// Profil rempli : on passe au code du propriétaire.
    func toPin() {
        guard canFinish else { return }
        error = nil
        withAnimation(Td.sortie) { step = .pin }
    }

    func finish(pin: String) {
        guard let photo, let jpeg = Self.squareJpeg(photo) else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            // Le Pi peut redémarrer (mise à jour) pendant qu'on remplit le profil : on le retrouve et on réessaie.
            let deadline = Date().addingTimeInterval(240)
            while true {
                do {
                    try await client.uploadPhoto(jpeg)
                    ownerKey = try await client.sendProfile(
                        firstName: firstName.trimmingCharacters(in: .whitespaces),
                        lastName: lastName.trimmingCharacters(in: .whitespaces),
                        nickname: nickname.trimmingCharacters(in: .whitespaces),
                        pin: pin
                    )
                    error = nil
                    UserDefaults.standard.set(true, forKey: "setupDone")
                    withAnimation(Td.sortie) { step = .done }
                    return
                } catch {
                    let retry: Bool
                    switch error as? PiError {
                    case .unreachable?: retry = true
                    case .http(401, _)?: retry = true
                    default: retry = false
                    }
                    guard retry, Date() < deadline else {
                        self.error = error.localizedDescription
                        return
                    }
                    self.error = "Le Pi ne répond pas, on le cherche..."
                    try? await Task.sleep(for: .seconds(3))
                    if (try? await client.relocate(port: link?.port ?? 8420)) != nil {
                        do { _ = try await client.status() } catch PiError.http(401, _) { try? await repair() } catch {}
                    }
                }
            }
        }
    }

    func back() {
        withAnimation(Td.sortie) {
            switch step {
            case .password: step = .wifi
            case .wifi: step = .scan
            case .scan: onExit()
            case .pin: step = .profile
            case .profile, .done: break
            }
        }
    }

    /// Carré centré, 720 px, JPEG.
    static func squareJpeg(_ img: UIImage) -> Data? {
        let side = min(img.size.width, img.size.height)
        let target: CGFloat = 720
        let scale = target / side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        let out = renderer.image { _ in
            let w = img.size.width * scale, h = img.size.height * scale
            img.draw(in: CGRect(x: (target - w) / 2, y: (target - h) / 2, width: w, height: h))
        }
        return out.jpegData(compressionQuality: 0.85)
    }
}
