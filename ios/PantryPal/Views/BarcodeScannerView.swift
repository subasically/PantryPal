import SwiftUI
@preconcurrency import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    @Binding var isPresented: Bool
    var onScan: ((String) -> Void)?
    
    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let viewController = BarcodeScannerViewController()
        viewController.onCodeFound = { [self] code in
            Task { @MainActor in
                scannedCode = code
                onScan?(code)
                isPresented = false
            }
        }
        viewController.onError = { error in
            print("Scanner error: \(error.localizedDescription)")
            Task { @MainActor [self] in
                isPresented = false
            }
        }
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

class BarcodeScannerViewController: UIViewController {
    var onCodeFound: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkCameraPermission()
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCamera()
                    }
                }
            }
        default:
            onError?(NSError(domain: "BarcodeScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera access denied"]))
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasScanned = false
        startSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }
    
    private func startSession() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    private func stopSession() {
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }
    
    private func setupCamera() {
        let captureSession = AVCaptureSession()
        self.captureSession = captureSession
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            onError?(NSError(domain: "BarcodeScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera available"]))
            return
        }
        
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            onError?(error)
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            onError?(NSError(domain: "BarcodeScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not add video input"]))
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .code93, .qr]
        } else {
            onError?(NSError(domain: "BarcodeScanner", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not add metadata output"]))
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        
        if let previewLayer = previewLayer {
            view.layer.addSublayer(previewLayer)
        }
        
        addScanOverlay()
        startSession()
    }
    
    private func addScanOverlay() {
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.isUserInteractionEnabled = false
        
        let scanAreaSize = CGSize(width: 280, height: 140)
        let scanAreaOrigin = CGPoint(
            x: (view.bounds.width - scanAreaSize.width) / 2,
            y: (view.bounds.height - scanAreaSize.height) / 2 - 50
        )
        let scanArea = CGRect(origin: scanAreaOrigin, size: scanAreaSize)
        
        let path = UIBezierPath(rect: overlayView.bounds)
        let scanPath = UIBezierPath(roundedRect: scanArea, cornerRadius: 12)
        path.append(scanPath)
        path.usesEvenOddFillRule = true
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        overlayView.layer.mask = maskLayer
        
        view.addSubview(overlayView)
        
        let borderView = UIView(frame: scanArea)
        borderView.layer.borderColor = UIColor.white.cgColor
        borderView.layer.borderWidth = 2
        borderView.layer.cornerRadius = 12
        borderView.backgroundColor = .clear
        view.addSubview(borderView)
        
        let label = UILabel()
        label.text = "Align barcode within frame"
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: borderView.bottomAnchor, constant: 20)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
}

extension BarcodeScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // Extract the string value on the current thread before dispatching
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.hasScanned else { return }
            
            self.hasScanned = true
            
            // Play barcode beep sound and haptic feedback
            HapticService.shared.barcodeScanSuccess()
            
            self.onCodeFound?(stringValue)
        }
    }
}

#Preview {
    BarcodeScannerView(scannedCode: .constant(nil), isPresented: .constant(true))
}
