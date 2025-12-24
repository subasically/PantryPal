import SwiftUI

struct SmartScannerView: View {
    @Binding var isPresented: Bool
    var onItemScanned: ((String, String?, Date?) -> Void)?
    
    @State private var currentStep = ScanStep.barcode
    @State private var scannedUPC: String?
    @State private var productName: String = ""
    @State private var expirationDate: Date?
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    
    enum ScanStep {
        case barcode
        case productPhoto
        case expirationPhoto
        case review
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                switch currentStep {
                case .barcode:
                    barcodeStep
                case .productPhoto:
                    productPhotoStep
                case .expirationPhoto:
                    expirationPhotoStep
                case .review:
                    reviewStep
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                if currentStep != .barcode && currentStep != .review {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Skip") {
                            nextStep()
                        }
                    }
                }
            }
        }
    }
    
    private var stepTitle: String {
        switch currentStep {
        case .barcode: return "Scan Barcode"
        case .productPhoto: return "Product Photo"
        case .expirationPhoto: return "Expiration Date"
        case .review: return "Review Item"
        }
    }
    
    // MARK: - Steps
    
    private var barcodeStep: some View {
        BarcodeScannerView(scannedCode: $scannedUPC, isPresented: .constant(true)) { code in
            scannedUPC = code
            // Try to lookup product first
            Task {
                isProcessing = true
                do {
                    let result = try await APIService.shared.lookupUPC(code)
                    if let product = result.product {
                        productName = product.name
                        // If found, jump to review or expiration?
                        // Let's go to expiration to be thorough
                        currentStep = .expirationPhoto
                    } else {
                        // Not found, need photo for name
                        currentStep = .productPhoto
                    }
                } catch {
                    currentStep = .productPhoto
                }
                isProcessing = false
            }
        }
    }
    
    private var productPhotoStep: some View {
        PhotoCaptureView(isPresented: .constant(true)) { image in
            capturedImage = image
            isProcessing = true
            Task {
                do {
                    let texts = try await OCRService.shared.recognizeText(from: image)
                    // Simple heuristic: longest string is likely the name
                    if let likelyName = texts.max(by: { $0.count < $1.count }) {
                        productName = likelyName
                    }
                } catch {
                    print("OCR Error: \(error)")
                }
                isProcessing = false
                nextStep()
            }
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.5)
                    ProgressView("Reading text...")
                        .tint(.white)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private var expirationPhotoStep: some View {
        PhotoCaptureView(isPresented: .constant(true)) { image in
            isProcessing = true
            Task {
                do {
                    let texts = try await OCRService.shared.recognizeText(from: image)
                    if let date = await OCRService.shared.extractExpirationDate(from: texts) {
                        expirationDate = date
                    }
                } catch {
                    print("OCR Error: \(error)")
                }
                isProcessing = false
                nextStep()
            }
        }
        .overlay {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.5)
                    ProgressView("Finding date...")
                        .tint(.white)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private var reviewStep: some View {
        Form {
            Section("Product Details") {
                TextField("Name", text: $productName)
                if let upc = scannedUPC {
                    Text("UPC: \(upc)")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Expiration") {
                if let date = expirationDate {
                    DatePicker("Expires", selection: Binding(get: { date }, set: { expirationDate = $0 }), displayedComponents: .date)
                } else {
                    Button("Add Expiration Date") {
                        expirationDate = Date()
                    }
                }
            }
            
            Section {
                Button("Add to Pantry") {
                    // Call API to add item
                    // For now just close and callback
                    onItemScanned?(productName, scannedUPC, expirationDate)
                    isPresented = false
                }
                .disabled(productName.isEmpty)
            }
        }
    }
    
    private func nextStep() {
        withAnimation {
            switch currentStep {
            case .barcode: currentStep = .productPhoto
            case .productPhoto: currentStep = .expirationPhoto
            case .expirationPhoto: currentStep = .review
            case .review: break
            }
        }
    }
}
