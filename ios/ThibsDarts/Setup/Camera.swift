import AVFoundation
import SwiftUI
import UIKit

/// Caméra partagée : lecture de QR code (dos) et photo de profil (selfie).
final class Camera: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "thibsdarts.camera")
    private let metadata = AVCaptureMetadataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var onCode: ((String) -> Void)?
    private var onPhoto: ((UIImage?) -> Void)?

    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var available = true

    static var hasCamera: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        AVCaptureDevice.default(for: .video) != nil
        #endif
    }

    func startScanning(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        start(position: .back, scanning: true)
    }

    func startSelfie() {
        start(position: .front, scanning: false)
    }

    func flip() {
        start(position: position == .front ? .back : .front, scanning: false)
    }

    func stop() {
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    func capture(_ done: @escaping (UIImage?) -> Void) {
        onPhoto = done
        queue.async { [self] in
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func start(position: AVCaptureDevice.Position, scanning: Bool) {
        guard Self.hasCamera else {
            DispatchQueue.main.async { self.available = false }
            return
        }
        AVCaptureDevice.requestAccess(for: .video) { [self] ok in
            guard ok else {
                DispatchQueue.main.async { self.available = false }
                return
            }
            queue.async { [self] in
                session.beginConfiguration()
                if let input { session.removeInput(input) }
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                   let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) {
                    session.addInput(newInput)
                    input = newInput
                }
                if scanning {
                    session.sessionPreset = .high
                    if !session.outputs.contains(metadata), session.canAddOutput(metadata) {
                        session.addOutput(metadata)
                        metadata.setMetadataObjectsDelegate(self, queue: .main)
                    }
                    if metadata.availableMetadataObjectTypes.contains(.qr) { metadata.metadataObjectTypes = [.qr] }
                } else {
                    session.sessionPreset = .photo
                    if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
                        session.addOutput(photoOutput)
                    }
                }
                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
                DispatchQueue.main.async { self.position = position }
            }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        onCode?(code)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        var image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        // Selfie : on remet l'image dans le sens du miroir, comme à l'écran.
        if let img = image, position == .front, let cg = img.cgImage {
            image = UIImage(cgImage: cg, scale: img.scale, orientation: .leftMirrored)
        }
        let done = onPhoto
        DispatchQueue.main.async { done?(image) }
    }
}

/// Aperçu vidéo plein cadre.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
