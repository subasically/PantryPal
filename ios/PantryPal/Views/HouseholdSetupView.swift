import SwiftUI

struct HouseholdSetupView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var showJoinSheet = false
    @State private var householdName = ""
    @State private var isRenaming = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(LinearGradient.ppPrimaryGradient)
                    
                    Text("Welcome to PantryPal!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("Let's get your household set up so you can start tracking your pantry.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Options
                VStack(spacing: 20) {
                    // Option 1: Create New (Default)
                    Button {
                        Task {
                            await authViewModel.completeHouseholdSetup()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "plus.square.fill")
                                    .font(.title2)
                                Text("Create New Household")
                                    .font(.headline)
                            }
                            Text("Start fresh with a new pantry inventory for you and your family.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    // Option 2: Join Existing
                    Button {
                        showJoinSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .font(.title2)
                                Text("Join Existing Household")
                                    .font(.headline)
                            }
                            Text("Have an invite code? Join an existing household to share inventory.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Logout option in case they want to switch accounts
                Button("Sign Out") {
                    authViewModel.logout()
                }
                .foregroundColor(.red)
                .padding(.bottom)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showJoinSheet) {
                JoinHouseholdOnboardingView()
            }
        }
    }
}

struct JoinHouseholdOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authViewModel
    @StateObject private var viewModel = JoinHouseholdViewModel()
    @State private var showScanner = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Code Entry
                VStack(spacing: 12) {
                    Text("Enter Invite Code")
                        .font(.headline)
                    
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { index in
                            CodeCharacterView(code: viewModel.code, index: index)
                        }
                    }
                    
                    TextField("Enter or paste code", text: $viewModel.code)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: viewModel.code) { _, newValue in
                            viewModel.code = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                            if viewModel.code.count == 6 {
                                Task {
                                    await viewModel.validateCode()
                                }
                            }
                        }
                }
                
                Button {
                    showScanner = true
                } label: {
                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Scan QR Code")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Divider()
                
                if viewModel.isValidating {
                    ProgressView("Validating code...")
                } else if let validation = viewModel.validationResult {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Color.ppTertiary)
                        
                        Text(validation.householdName)
                            .font(.title2.bold())
                        
                        Text("\(validation.memberCount) member\(validation.memberCount == 1 ? "" : "s")")
                            .foregroundColor(.secondary)
                        
                        Button {
                            Task {
                                await viewModel.joinHousehold()
                                if viewModel.showSuccess {
                                    await authViewModel.completeHouseholdSetup()
                                    dismiss()
                                }
                            }
                        } label: {
                            Text("Join Household")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ppPrimary)
                        .disabled(viewModel.isJoining)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Join Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { code in
                    viewModel.code = code.uppercased()
                    showScanner = false
                    Task {
                        await viewModel.validateCode()
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
}

#Preview {
    HouseholdSetupView()
        .environment(AuthViewModel())
}
