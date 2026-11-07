import Foundation
import Network
import NetworkExtension

/// Infos lues dans le QR code du Pi : thibsdarts://setup?h=10.42.0.1&p=8420&c=4821&s=ThibsDarts-4821&k=...
struct SetupLink: Equatable {
    var host: String?
    var port: Int = 8420
    var code: String
    var ssid: String?
    var key: String?

    init?(url: URL) {
        guard url.scheme == "thibsdarts", url.host == "setup",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func q(_ n: String) -> String? { items.first { $0.name == n }?.value }
        guard let c = q("c"), c.count == 4 else { return nil }
        code = c
        host = q("h")
        port = Int(q("p") ?? "") ?? 8420
        ssid = q("s")
        key = q("k")
    }

    init(code: String) {
        self.code = code
    }
}

struct WifiNetwork: Decodable, Identifiable, Hashable {
    let name: String
    let signal: Int
    let locked: Bool
    var id: String { name }
}

struct SetupStatus: Decodable {
    let phase: String
    let wifi: String
    let ssid: String?
}


/// Parle au serveur de setup du Pi 4 (port 8420).
final class PiClient {
    private(set) var base: URL?
    private(set) var token: String?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Rejoint le Wi-Fi du Pi (iOS demande l'autorisation). Sans l'entitlement Hotspot, ça échoue :
    /// l'utilisateur rejoint alors le réseau à la main dans Réglages.
    func joinHotspot(ssid: String, key: String?) async -> Bool {
        let conf = key.map { NEHotspotConfiguration(ssid: ssid, passphrase: $0, isWEP: false) }
            ?? NEHotspotConfiguration(ssid: ssid)
        conf.joinOnce = true
        do {
            try await NEHotspotConfigurationManager.shared.apply(conf)
            return true
        } catch let e as NSError where e.domain == NEHotspotConfigurationErrorDomain
            && e.code == NEHotspotConfigurationError.alreadyAssociated.rawValue {
            return true
        } catch {
            return false
        }
    }

    func leaveHotspot(ssid: String) {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }

    /// Trouve le Pi : adresse du QR, Bonjour, passerelle du hotspot, puis le Mac en simulateur.
    func locate(preferred host: String?, port: Int) async throws -> URL {
        var candidates: [String] = []
        if let host { candidates.append(host) }
        candidates += await Bonjour.find(timeout: 2.5)
        candidates.append("10.42.0.1")
        #if targetEnvironment(simulator)
        candidates.append("127.0.0.1")
        #endif
        for h in candidates {
            let hostPart = h.contains(":") && !h.contains("]") ? "[\(h)]" : h
            guard let url = URL(string: "http://\(hostPart):\(port)") else { continue }
            if await hello(url) { return url }
        }
        throw PiError.unreachable
    }

    private func hello(_ url: URL) async -> Bool {
        var req = URLRequest(url: url.appendingPathComponent("api/setup/hello"))
        req.timeoutInterval = 2.5
        guard let (data, res) = try? await session.data(for: req),
              (res as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return j["device"] as? String == "ThibsDarts"
    }

    func pair(at url: URL, code: String, device: String) async throws {
        base = url
        let (status, data) = try await send("POST", "api/setup/pair", json: ["code": code, "device": device], auth: false)
        if status == 403 { throw PiError.badCode }
        guard status == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = j["token"] as? String else { throw PiError.http(status, "appairage") }
        token = t
    }

    /// Après un changement de réseau : retrouve le Pi en gardant la session.
    func relocate(port: Int) async throws {
        base = try await locate(preferred: nil, port: port)
    }

    func networks() async throws -> [WifiNetwork] {
        struct R: Decodable { let networks: [WifiNetwork] }
        let (status, data) = try await send("GET", "api/setup/networks")
        guard status == 200 else { throw PiError.http(status, "réseaux") }
        return try JSONDecoder().decode(R.self, from: data).networks
    }

    func sendWifi(ssid: String, password: String) async throws {
        let (status, _) = try await send("POST", "api/setup/wifi", json: ["ssid": ssid, "password": password])
        guard status == 202 else { throw PiError.http(status, "Wi-Fi") }
    }

    func status() async throws -> SetupStatus {
        let (status, data) = try await send("GET", "api/setup/status")
        guard status == 200 else { throw PiError.http(status, "état") }
        return try JSONDecoder().decode(SetupStatus.self, from: data)
    }

    func uploadPhoto(_ jpeg: Data) async throws {
        let (status, _) = try await send("PUT", "api/setup/photo", body: jpeg, contentType: "image/jpeg")
        guard status == 200 else { throw PiError.http(status, "photo") }
    }

    /// Envoie le profil du propriétaire. Renvoie la clé de son profil sur la cible.
    func sendProfile(firstName: String, lastName: String, nickname: String, pin: String) async throws -> String {
        let (status, data) = try await send(
            "POST", "api/setup/profile",
            json: ["firstName": firstName, "lastName": lastName, "nickname": nickname, "pin": pin]
        )
        guard status == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = j["playerToken"] as? String else { throw PiError.http(status, "profil") }
        return key
    }

    private func send(
        _ method: String, _ path: String, json: [String: String]? = nil,
        body: Data? = nil, contentType: String? = nil, auth: Bool = true
    ) async throws -> (Int, Data) {
        guard let base else { throw PiError.unreachable }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let body {
            req.httpBody = body
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if auth, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, res) = try await session.data(for: req)
            return ((res as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw PiError.unreachable
        }
    }
}

/// Cherche les ThibsDarts annoncés en Bonjour (_thibsdarts._tcp) et renvoie leurs adresses.
enum Bonjour {
    static func find(timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { cont in
            let browser = NWBrowser(for: .bonjour(type: "_thibsdarts._tcp", domain: nil), using: .tcp)
            let lock = NSLock()
            var done = false
            var hosts: [String] = []
            func finish() {
                lock.lock()
                defer { lock.unlock() }
                guard !done else { return }
                done = true
                browser.cancel()
                cont.resume(returning: hosts)
            }
            browser.browseResultsChangedHandler = { results, _ in
                for r in results {
                    if case let .service(name, _, _, _) = r.endpoint {
                        // Le Pi s'annonce avec son nom d'hôte, résolu en .local.
                        lock.lock()
                        hosts.append("\(name).local")
                        lock.unlock()
                    }
                }
            }
            browser.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish() }
        }
    }
}
