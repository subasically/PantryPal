import SwiftUI

struct UPCScannerSheet: View {
    @Binding var scannedUPC: String
    @Binding var isPresented: Bool
    
    @State private var tempCode: String?
    @State private var isScanning = true
    
    var body: some View {
        NavigationStack {
            VStack {
                if let code = tempCode {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.ppGreen)
                        
                        Text("Barcode Scanned")
                            .font(.headline)
                        
                        Text(code)
                            .font(.title2)
                            .fontWeight(.medium)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        
                        HStack(spacing: 16) {
                            Button("Scan Again") {
                                tempCode = nil
                                isScanning = true
                            }
                            .buttonStyle(.ppSecondary)
                            
                            Button("Use This Code") {
                                scannedUPC = code
                                isPresented = false
                            }
                            .buttonStyle(.ppPrimary)
                        }
                    }
                    .padding()
                } else {
                    BarcodeScannerView(scannedCode: $tempCode, isPresented: .constant(true), isScanning: $isScanning) { code in
                        tempCode = code
                    }
                }
            }
            .navigationTitle("Scan UPC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    InventoryListView()
        .environment(AuthViewModel())
}
