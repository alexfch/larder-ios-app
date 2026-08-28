import SwiftUI
import AVFoundation

/// Custom AVFoundation-based camera capture for a product photo, offered as an alternative to
/// `PhotosPicker`'s library-only selection in `NewProductFormView`. Mirrors `BarcodeScannerView`'s
/// approach — a capture UI matching the app's own design system rather than
/// `UIImagePickerController`'s system-provided camera UI. `NewProductFormView` only offers this
/// option on real hardware (the Simulator has no camera), so this view's job is handling the
/// camera *permission* states explicitly — not yet determined, denied, or granted — rather than
/// assuming access up front.
struct ProductCameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onCapture: (Data) -> Void

    @State private var controller: ProductCameraController?
    @State private var isCapturing = false
    @State private var authorizationStatus: AVAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Take Photo")
                    .font(LarderFont.screenTitle())
                    .foregroundStyle(.white)
                Spacer()
                Button("Cancel") { dismiss() }
                    .foregroundStyle(.white)
            }
            .padding(20)

            switch authorizationStatus {
            case .authorized:
                ZStack(alignment: .bottom) {
                    CameraControllerRepresentable(controller: $controller)

                    Button {
                        capture()
                    } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(Color.larderSecondaryText, lineWidth: 3))
                            .opacity(isCapturing ? 0.4 : 1)
                    }
                    .disabled(isCapturing)
                    .padding(.bottom, 30)
                }
            case .denied, .restricted:
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "camera.metering.unknown")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                    Text("Camera access is off for Larder.\nEnable it in Settings to take a photo.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .foregroundStyle(Color.larderAccent)
                }
                Spacer()
            case .notDetermined:
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            @unknown default:
                Spacer()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            // Request access here, before the capture session is ever configured, rather than
            // letting AVFoundation configuration silently no-op on missing authorization — see
            // ProductCameraController.viewDidLoad, which only runs once this view has already
            // confirmed .authorized.
            let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if currentStatus == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                authorizationStatus = granted ? .authorized : .denied
            } else {
                authorizationStatus = currentStatus
            }
        }
    }

    private func capture() {
        guard let controller, !isCapturing else { return }
        isCapturing = true
        controller.capturePhoto { data in
            isCapturing = false
            guard let data else { return }
            onCapture(data)
            dismiss()
        }
    }
}

/// Hands the underlying `ProductCameraController` back to the SwiftUI shell via `controller`, so
/// the shutter button — which has to live in SwiftUI to match the app's design system, not as a
/// UIKit subview like `capturePhoto`'s AVFoundation plumbing — can trigger a capture on it.
/// Setting the binding is deferred to the next run loop turn since `makeUIViewController` runs
/// during a SwiftUI view update, where synchronous state mutation isn't allowed.
private struct CameraControllerRepresentable: UIViewControllerRepresentable {
    @Binding var controller: ProductCameraController?

    func makeUIViewController(context: Context) -> ProductCameraController {
        let controller = ProductCameraController()
        DispatchQueue.main.async { self.controller = controller }
        return controller
    }

    func updateUIViewController(_ uiViewController: ProductCameraController, context: Context) {}
}

final class ProductCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureCompletion: ((Data?) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        session.beginConfiguration()
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(photoOutput)
        session.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session.stopRunning()
    }

    func capturePhoto(completion: @escaping (Data?) -> Void) {
        captureCompletion = completion
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        DispatchQueue.main.async { [weak self] in
            self?.captureCompletion?(data)
            self?.captureCompletion = nil
        }
    }
}
