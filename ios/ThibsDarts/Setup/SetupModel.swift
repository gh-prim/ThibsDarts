import SwiftUI
import UIKit

/// Parcours d'installation du premier allumage (planches "5. Premier allumage par QR code").
@MainActor
final class SetupModel: ObservableObject {
    enum Step: Equatable { case scan, wifi, password, profile, done }

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

    @Published var firstName = ""
    @Published var lastName = ""
    @Published var nickname = ""
    @Published var photo: UIImage?

    let client = PiClient()
    private var link: SetupLink?

    var progressIndex: Int {
        switch step {
        case .scan: 0
        case .wifi, .password: 1
        case .profile, .done: 2
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
                withAnimation(Td.sortie) { step = .wifi }
                loadNetworks()
            } catch {
                found = nil
                if let ssid = l.ssid, isUnreachable(error) {
                    self.error = "Rejoins le Wi-Fi \(ssid) dans Réglages, puis rescanne."
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
    /// et retrouve le Pi en Bonjour.
    private func waitForWifi() async throws {
        let deadline = Date().addingTimeInterval(60)
        var leftHotspot = false
        while Date() < deadline {
            try? await Task.sleep(for: .seconds(1))
            do {
                let s = try await client.status()
                if s.wifi == "ok" {
                    wifiState = .success
                    try? await Task.sleep(for: .milliseconds(900))
                    withAnimation(Td.sortie) { step = .profile }
                    return
                }
                if s.wifi == "error" {
                    wifiState = .error
                    return
                }
            } catch {
                if !leftHotspot, let ssid = link?.ssid {
                    leftHotspot = true
                    client.leaveHotspot(ssid: ssid)
                    try? await Task.sleep(for: .seconds(4))
                }
                try? await client.relocate(port: link?.port ?? 8420)
            }
        }
        wifiState = .error
    }

    // MARK: Étape 3 : profil et photo

    var canFinish: Bool {
        photo != nil && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func finish() {
        guard let photo, let jpeg = Self.squareJpeg(photo) else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await client.uploadPhoto(jpeg)
                try await client.sendProfile(
                    firstName: firstName.trimmingCharacters(in: .whitespaces),
                    lastName: lastName.trimmingCharacters(in: .whitespaces),
                    nickname: nickname.trimmingCharacters(in: .whitespaces)
                )
                UserDefaults.standard.set(true, forKey: "setupDone")
                withAnimation(Td.sortie) { step = .done }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func back() {
        withAnimation(Td.sortie) {
            switch step {
            case .password: step = .wifi
            case .wifi: step = .scan
            case .profile, .scan, .done: break
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
