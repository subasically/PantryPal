import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @EnvironmentObject private var notificationService: NotificationService
    @Environment(\.dismiss) private var dismiss
    
    @State private var biometricEnabled: Bool
    @State private var showingDisableAlert = false
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    init() {
        _biometricEnabled = State(initialValue: BiometricAuthService.shared.isBiometricLoginEnabled)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // User Info Section
                if let user = authViewModel.currentUser {
                    Section("Account") {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.ppPurple)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Notifications Section
                Section("Notifications") {
                    if notificationService.isAuthorized {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundColor(.ppGreen)
                                .frame(width: 24)
                            Text("Notifications enabled")
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.ppGreen)
                        }
                        
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "gear")
                                    .foregroundColor(.ppPurple)
                                    .frame(width: 24)
                                Text("Manage in Settings")
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "bell.slash.fill")
                                .foregroundColor(.ppOrange)
                                .frame(width: 24)
                            Text("Notifications disabled")
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            Task {
                                await notificationService.requestAuthorization()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.ppPurple)
                                    .frame(width: 24)
                                Text("Enable Notifications")
                            }
                        }
                    }
                }
                
                // Security Section
                Section("Security") {
                    if authViewModel.isBiometricAvailable {
                        Toggle(isOn: $biometricEnabled) {
                            HStack {
                                Image(systemName: authViewModel.biometricIcon)
                                    .foregroundColor(.ppPurple)
                                    .frame(width: 24)
                                Text("Sign in with \(authViewModel.biometricName)")
                            }
                        }
                        .onChange(of: biometricEnabled) { oldValue, newValue in
                            if !newValue {
                                showingDisableAlert = true
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "faceid")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("Biometric login not available")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Locations Section
                Section("Storage Locations") {
                    NavigationLink {
                        LocationsSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.ppGreen)
                                .frame(width: 24)
                            Text("Manage Locations")
                        }
                    }
                }
                
                // Household Section
                Section("Household") {
                    NavigationLink {
                        HouseholdSharingView()
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.ppPurple)
                                .frame(width: 24)
                            Text("Household Sharing")
                        }
                    }
                }
                
                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Sign Out Section
                Section {
                    Button(role: .destructive) {
                        authViewModel.logout()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Disable \(authViewModel.biometricName)?", isPresented: $showingDisableAlert) {
                Button("Cancel", role: .cancel) {
                    biometricEnabled = true
                }
                Button("Disable", role: .destructive) {
                    authViewModel.disableBiometricLogin()
                }
            } message: {
                Text("You will need to enter your email and password to sign in.")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthViewModel())
        .environmentObject(NotificationService.shared)
}
