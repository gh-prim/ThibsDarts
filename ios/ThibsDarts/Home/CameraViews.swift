import SwiftUI
import UIKit

// MARK: Caméras du Pi 5

/// État d'une caméra, relayé par le Pi 4 (GET /api/cams).
struct CamInfo: Decodable, Identifiable {
    let name: String
    let online: Bool
    let fps: Double
    let width: Int?
    let height: Int?

    var id: String { name }

    var detail: String {
        guard online else { return "débranchée" }
        guard let width, let height else { return "en veille" }
        return "\(width)x\(height) · \(Int(fps.rounded())) i/s"
    }
}

/// Flux MJPEG d'une caméra, relayé par le Pi 4 avec la clé du propriétaire.
@MainActor
final class MJPEGStream: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published private(set) var image: UIImage?
    @Published private(set) var failed = false

    private var session: URLSession?
    private var buffer = Data()
    private var request: URLRequest?
    private var retry: Task<Void, Never>?

    func start(_ req: URLRequest) {
        request = req
        connect()
    }

    func stop() {
        retry?.cancel()
        session?.invalidateAndCancel()
        session = nil
    }

    private func connect() {
        guard let request else { return }
        session?.invalidateAndCancel()
        buffer.removeAll()
        let s = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        session = s
        s.dataTask(with: request).resume()
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated {
            buffer.append(data)
            guard let frame = takeJpeg() else { return }
            image = UIImage(data: frame)
            failed = false
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated {
            guard session === self.session else { return }
            failed = true
            retry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { self?.connect() }
            }
        }
    }

    /// Dernière image JPEG complète (FFD8 ... FFD9) du tampon ; le reste est gardé.
    private func takeJpeg() -> Data? {
        let bytes = [UInt8](buffer)
        var end: Int?
        var i = bytes.count - 2
        while i >= 0 {
            if end == nil {
                if bytes[i] == 0xFF && bytes[i + 1] == 0xD9 { end = i + 2 }
            } else if bytes[i] == 0xFF && bytes[i + 1] == 0xD8 {
                let frame = Data(bytes[i..<end!])
                buffer = Data(bytes[end!...])
                return frame
            }
            i -= 1
        }
        if buffer.count > 4 << 20 { buffer.removeAll() }
        return nil
    }
}

/// Une caméra en direct.
struct CameraFeed: View {
    @EnvironmentObject private var app: AppModel
    let name: String
    @StateObject private var stream = MJPEGStream()

    var body: some View {
        ZStack {
            Td.betonNuit
            if let image = stream.image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Icon(name: stream.failed ? .x : .loaderCircle, size: 28).foregroundStyle(Td.ink3)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .onAppear {
            guard let base = app.piBase else { return }
            var req = URLRequest(url: base.appendingPathComponent("api/cams/\(name).mjpg"))
            req.timeoutInterval = 8
            app.authorize(&req)
            stream.start(req)
        }
        .onDisappear { stream.stop() }
    }
}

/// Réglages > Caméras (propriétaire) : les 3 caméras en direct, une en grand au toucher.
struct CamerasView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var cams: [CamInfo] = []
    @State private var error: String?
    @State private var zoomed: String?

    private let names = ["A", "B", "C"]

    var body: some View {
        Stage {
            VStack(spacing: Td.s4) {
                NavBar(title: "Caméras", back: "Retour") { dismiss() }
                ScrollView {
                    VStack(spacing: Td.s4) {
                        if let error { Banner(text: error, error: true) }
                        ForEach(names, id: \.self) { name in
                            VStack(alignment: .leading, spacing: Td.s2) {
                                CameraFeed(name: name)
                                    .clipShape(RoundedRectangle(cornerRadius: Td.rMd))
                                    .onTapGesture { zoomed = name }
                                label(name)
                            }
                        }
                        Text("Touche une caméra pour la voir en grand.")
                            .font(.td(13))
                            .foregroundStyle(Td.ink3)
                    }
                }
            }
            .padding(.horizontal, Td.s4)
            .padding(.top, 6)
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .fullScreenCover(item: Binding(get: { zoomed.map(Zoom.init) }, set: { zoomed = $0?.id })) { z in
            ZStack(alignment: .bottomLeading) {
                Td.betonNuit.ignoresSafeArea()
                CameraFeed(name: z.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                label(z.id).padding(Td.s4)
            }
            .environmentObject(app)
            .onTapGesture { zoomed = nil }
        }
    }

    private struct Zoom: Identifiable { let id: String }

    private func label(_ name: String) -> some View {
        let info = cams.first { $0.name == name }
        return HStack(spacing: Td.s2) {
            Circle().fill(info?.online == true ? Td.succes : Td.erreur).frame(width: 10, height: 10)
            Text("Caméra \(name)").font(.td(15, .semibold))
            Spacer()
            Text(info?.detail ?? "…").font(.td(13)).foregroundStyle(Td.ink2)
        }
    }

    private func refresh() async {
        guard let base = app.piBase else { return }
        var req = URLRequest(url: base.appendingPathComponent("api/cams"))
        req.timeoutInterval = 5
        app.authorize(&req)
        struct Status: Decodable { let cams: [CamInfo] }
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            switch (res as? HTTPURLResponse)?.statusCode {
            case 200:
                cams = try JSONDecoder().decode(Status.self, from: data).cams
                error = nil
            case 401: error = "Réservé au propriétaire de la cible."
            default: error = "Le Pi 5 des caméras ne répond pas."
            }
        } catch {
            self.error = "Cible injoignable."
        }
    }
}
