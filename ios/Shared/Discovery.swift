import Darwin
import Foundation

/// Cible ThibsDarts trouvée sur le Wi-Fi.
struct FoundPi: Identifiable, Hashable {
    let base: URL
    let owner: String
    var id: String { base.absoluteString }
}

/// Cherche les cibles : d'abord cet appareil (simulateur), puis tout le réseau local en /24.
enum Discovery {
    static func scan() async -> [FoundPi] {
        // Simulateur : le hub tourne sur le Mac, inutile de balayer le réseau.
        if let me = await probe(URL(string: "http://127.0.0.1:8420")!) { return [me] }
        var hosts: [String] = []
        if let ip = localIPv4() {
            let parts = ip.split(separator: ".")
            if parts.count == 4 {
                let prefix = parts.prefix(3).joined(separator: ".")
                hosts += (1...254).map { "\(prefix).\($0)" }.filter { $0 != ip }
            }
        }
        let urls = hosts.compactMap { URL(string: "http://\($0):8420") }
        return await withTaskGroup(of: FoundPi?.self) { group in
            var out: [FoundPi] = []
            var next = 0
            while next < min(48, urls.count) {
                let url = urls[next]
                next += 1
                group.addTask { await probe(url) }
            }
            while let r = await group.next() {
                if let r, !out.contains(where: { $0.owner == r.owner }) { out.append(r) }
                if next < urls.count {
                    let url = urls[next]
                    next += 1
                    group.addTask { await probe(url) }
                }
            }
            return out
        }
    }

    private static func probe(_ url: URL) async -> FoundPi? {
        guard let h = await LobbyAPI.hello(at: url, timeout: 1.5) else { return nil }
        return FoundPi(base: url, owner: h.owner ?? "Thibs")
    }

    /// Adresse IPv4 Wi-Fi ou Ethernet de l'Apple TV.
    static func localIPv4() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var best: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: a.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if name == "en0" { return ip }
                best = best ?? ip
            }
        }
        return best
    }
}
