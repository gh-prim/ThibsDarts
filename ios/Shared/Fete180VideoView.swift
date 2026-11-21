import AVFoundation
import SwiftUI
import UIKit

/// Vidéo 180 (clip Blender, 6 s, avec son) en plein écran. onEnd part à la fin ou au toucher.
struct Fete180VideoView: View {
    var onEnd: () -> Void

    var body: some View {
        Fete180Player(onEnd: onEnd)
            .background(Color.black)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { onEnd() }
    }
}

private struct Fete180Player: UIViewRepresentable {
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .black
        guard let url = Bundle.main.url(forResource: "fete180", withExtension: "mp4") else {
            DispatchQueue.main.async { onEnd() }
            return view
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        let player = AVPlayer(url: url)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        context.coordinator.end = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { _ in onEnd() }
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        uiView.playerLayer.player?.pause()
        uiView.playerLayer.player = nil
        if let end = coordinator.end { NotificationCenter.default.removeObserver(end) }
    }

    final class Coordinator { var end: NSObjectProtocol? }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
