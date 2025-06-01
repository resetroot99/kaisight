import AVFoundation
import UIKit

class CameraManager: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    @Published var capturedImage: UIImage?

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        session.beginConfiguration()
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input), session.canAddOutput(output) else {
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    func getSession() -> AVCaptureSession {
        return session
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let data = photo.fileDataRepresentation() {
            capturedImage = UIImage(data: data)
        }
    }
} 