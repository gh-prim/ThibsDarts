import SwiftUI
import UIKit

// MARK: Caméras du Pi 5

/// État d'une caméra, relayé par le Pi 4 (GET /api/cams). Les caméras sont toutes identiques :
/// le Pi 5 les reconnaît à leur vue, quel que soit le port USB.
struct CamInfo: Decodable, Identifiable {
    /// Identifiant du flux sur le Pi 5 (change si on change la caméra de port).
    let id: String
    /// Nom choisi par le propriétaire ("Haut", "Gauche").
    let label: String?
    let online: Bool
    let fps: Double
    let width: Int?
    let height: Int?
    /// La caméra voit bouger quelque chose (main passée devant pour la repérer).
    let moving: Bool

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
    let id: String
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
            var req = URLRequest(url: base.appendingPathComponent("api/cams/\(id).mjpg"))
            req.timeoutInterval = 8
            app.authorize(&req)
            stream.start(req)
        }
        .onDisappear { stream.stop() }
    }
}

/// Réglages > Caméras (propriétaire) : les caméras en direct, une en grand au toucher.
struct CamerasView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var cams: [CamInfo] = []
    @State private var known: [String] = []
    @State private var error: String?
    @State private var zoomed: String?
    @State private var renaming: CamInfo?
    @State private var newName = ""

    var body: some View {
        Stage {
            VStack(spacing: Td.s4) {
                NavBar(title: "Caméras", back: "Retour") { dismiss() }
                ScrollView {
                    VStack(spacing: Td.s4) {
                        if let error { Banner(text: error, error: true) }
                        Text("✋ Passe la main devant une caméra pour la repérer : sa vignette s’allume.")
                            .font(.td(13))
                            .foregroundStyle(Td.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(Array(cams.enumerated()), id: \.element.id) { i, cam in
                            VStack(alignment: .leading, spacing: Td.s2) {
                                CameraFeed(id: cam.id)
                                    .clipShape(RoundedRectangle(cornerRadius: Td.rMd))
                                    .padding(3)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Td.rMd + 3)
                                            .strokeBorder(cam.moving ? Td.fluo : Td.verreBord, lineWidth: 2)
                                    )
                                    .shadow(color: cam.moving ? Td.sunset.opacity(0.55) : .clear, radius: 14)
                                    .animation(.easeOut(duration: 0.18), value: cam.moving)
                                    .onTapGesture { zoomed = cam.id }
                                label(cam, number: i + 1)
                                HStack {
                                    Text(state(cam))
                                        .font(.td(13))
                                        .foregroundStyle(cam.label == nil && !known.isEmpty ? Td.sunset : Td.ink3)
                                    Spacer()
                                    TdButton(title: "Nommer", variant: .secondary, size: .sm) {
                                        newName = cam.label ?? ""
                                        renaming = cam
                                    }
                                }
                            }
                        }
                        Text("Touche une caméra pour la voir en grand. Une caméra nommée garde son nom même branchée sur un autre port : le Pi 5 la reconnaît à ce qu’elle voit.")
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
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        .alert(
            "Nommer la caméra",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Haut, Gauche, Droite…", text: $newName)
            Button("Enregistrer") { if let cam = renaming { Task { await rename(cam.id, newName) } } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("D’après sa place autour de la cible. Fixe-la d’abord. Laisse vide pour enlever le nom.")
        }
        .fullScreenCover(item: Binding(get: { zoomed.map(Zoom.init) }, set: { zoomed = $0?.id })) { z in
            ZStack(alignment: .bottomLeading) {
                Td.betonNuit.ignoresSafeArea()
                CameraFeed(id: z.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let i = cams.firstIndex(where: { $0.id == z.id }) {
                    label(cams[i], number: i + 1).padding(Td.s4)
                }
            }
            .environmentObject(app)
            .onTapGesture { zoomed = nil }
        }
    }

    private struct Zoom: Identifiable { let id: String }

    private func state(_ cam: CamInfo) -> String {
        if cam.label != nil { return "Reconnue" }
        return known.isEmpty ? "Sans nom" : "Non reconnue"
    }

    private func label(_ cam: CamInfo, number: Int) -> some View {
        HStack(spacing: Td.s2) {
            Circle().fill(cam.online ? Td.succes : Td.erreur).frame(width: 10, height: 10)
            Text(cam.label ?? "Caméra \(number)")
                .font(.td(15, .semibold))
                .foregroundStyle(cam.moving ? Td.fluo : Td.ink)
            Spacer()
            Text(cam.detail).font(.td(13)).foregroundStyle(Td.ink2)
        }
    }

    private func rename(_ cam: String, _ name: String) async {
        guard let base = app.piBase else { return }
        var req = URLRequest(url: base.appendingPathComponent("api/cams/\(cam)/name"))
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["name": name.trimmingCharacters(in: .whitespaces)])
        app.authorize(&req)
        _ = try? await URLSession.shared.data(for: req)
        await refresh()
    }

    private func refresh() async {
        guard let base = app.piBase else { return }
        var req = URLRequest(url: base.appendingPathComponent("api/cams"))
        req.timeoutInterval = 5
        app.authorize(&req)
        struct Status: Decodable {
            let cams: [CamInfo]
            let known: [String]?
        }
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            switch (res as? HTTPURLResponse)?.statusCode {
            case 200:
                let status = try JSONDecoder().decode(Status.self, from: data)
                cams = status.cams
                known = status.known ?? []
                error = nil
            case 401: error = "Réservé au propriétaire de la cible."
            default: error = "Le Pi 5 des caméras ne répond pas."
            }
        } catch {
            self.error = "Cible injoignable."
        }
    }
}
