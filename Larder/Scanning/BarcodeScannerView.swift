import SwiftUI
import AVFoundation

/// Custom AVFoundation-based scanner so the scan UI matches the app's own design system
/// rather than a system-provided one. The Simulator has no camera, so this falls back to a
/// manual code entry field there, which also doubles as a quick way to exercise the
/// unmatched-barcode → New Product path without physical hardware.
struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void

    @State private var manualCode: String = ""

    private var cameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    var body: some View {
        // Full-screen sheet again (no `.presentationDetents`), but the camera preview itself is
        // capped to the top half via `GeometryReader` — the only clean way in SwiftUI to size a
        // view to a fraction of the available space, since a plain `.frame` can't express "50%".
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Text("Scan")
                        .font(LarderFont.screenTitle())
                    Spacer()
                    Button("Cancel") { dismiss() }
                }
                .padding(20)

                if cameraAvailable {
                    ZStack {
                        CameraPreview { code in
                            onCode(code)
                        }
                        // Wide/short reticle matching a barcode's own proportions, rather than
                        // the old uniform-padding square.
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.larderAccent, lineWidth: 3)
                            .aspectRatio(2.4, contentMode: .fit)
                            .padding(.horizontal, 32)
                    }
                    .frame(height: geometry.size.height / 3)
                    .clipped()

                    Spacer()
                } else {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "camera.metering.unknown")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.larderSecondaryText)
                        Text("Camera not available in Simulator.\nEnter a barcode to simulate a scan.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.larderSecondaryText)
                        TextField("Barcode", text: $manualCode)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .overlay(Rectangle().strokeBorder(Color.larderDivider, lineWidth: 1))
                            .padding(.horizontal, 60)
                        PrimaryButton(title: "Simulate Scan", isEnabled: !manualCode.isEmpty) {
                            onCode(manualCode)
                        }
                        .padding(.horizontal, 60)
                    }
                    Spacer()
                }
            }
        }
        .background(Color.larderBackground.ignoresSafeArea())
    }
}

private struct CameraPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .qr]

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

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        session.stopRunning()
        onCode?(value)
    }
}
