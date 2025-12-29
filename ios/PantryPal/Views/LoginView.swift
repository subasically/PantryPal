import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.colorScheme) var colorScheme
    
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isRegistering = false
    @State private var showEmailForm = false
    @State private var showOtherOptions = false
    
    var body: some View {
        @Bindable var authViewModel = authViewModel
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 32) {
                        // Logo/Title
                        VStack(spacing: 16) {
                            Image(systemName: "refrigerator.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(LinearGradient.ppPrimaryGradient)
                                .padding(.bottom, 8)
                            
                            Text("PantryPal")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.ppPurple)
                            
                            Text("Track your pantry inventory")
                                .font(.title3)
                                .foregroundColor(.ppSecondaryText)
                        }
                        .padding(.top, 60)
                        .padding(.bottom, 20)
                        
                        if !showEmailForm {
                            VStack(spacing: 16) {
                                // Returning User Flow: Face ID Primary
                                if authViewModel.canUseBiometricLogin && !showOtherOptions {
                                    Button(action: {
                                        Task {
                                            await authViewModel.loginWithBiometrics()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: authViewModel.biometricIcon)
                                            Text("Sign in with \(authViewModel.biometricName)")
                                        }
                                    }
                                    .buttonStyle(.ppPrimary)
                                    
                                    Button("Use a different account") {
                                        withAnimation {
                                            showOtherOptions = true
                                        }
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.ppPurple)
                                    .padding(.top, 8)
                                    
                                } else {
                                    // New User / Other Options Flow: Apple Primary
                                    SignInWithAppleButton(.continue) { request in
                                        request.requestedScopes = [.fullName, .email]
                                    } onCompletion: { result in
                                        Task {
                                            await authViewModel.handleAppleSignIn(result: result)
                                        }
                                    }
                                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                                    .frame(height: 50)
                                    .cornerRadius(10)
                                    
                                    if let error = authViewModel.errorMessage {
                                        Text(error)
                                            .foregroundColor(.red)
                                            .font(.caption)
                                            .multilineTextAlignment(.center)
                                            .padding(.top, 4)
                                    }
                                    
                                    Text("No spam. Just to sync your pantry.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    // Use Email Option
                                    Button(action: {
                                        withAnimation {
                                            showEmailForm = true
                                        }
                                    }) {
                                        Text("Continue with email")
                                            .fontWeight(.medium)
                                    }
                                    .padding(.top, 8)
                                    
                                    // Back to Face ID if available
                                    if authViewModel.canUseBiometricLogin {
                                        Button("Back to \(authViewModel.biometricName)") {
                                            withAnimation {
                                                showOtherOptions = false
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 16)
                                    }
                                }
                            }
                            .padding(.horizontal, 32)
                        } else {
                            // Email Form
                            VStack(spacing: 20) {
                                VStack(spacing: 16) {
                                    if isRegistering {
                                        TextField("Name", text: $name)
                                            .textFieldStyle(.roundedBorder)
                                            .textContentType(.name)
                                    }
                                    
                                    TextField("Email", text: $email)
                                        .textFieldStyle(.roundedBorder)
                                        .textContentType(.emailAddress)
                                        .autocapitalization(.none)
                                        .keyboardType(.emailAddress)
                                    
                                    SecureField("Password", text: $password)
                                        .textFieldStyle(.roundedBorder)
                                        .textContentType(isRegistering ? .newPassword : .password)
                                }
                                
                                if let error = authViewModel.errorMessage {
                                    Text(error)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                }
                                
                                Button(action: {
                                    Task {
                                        if isRegistering {
                                            await authViewModel.register(
                                                email: email,
                                                password: password,
                                                name: name
                                            )
                                        } else {
                                            await authViewModel.login(email: email, password: password)
                                        }
                                    }
                                }) {
                                    if authViewModel.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text(isRegistering ? "Create Account" : "Sign In")
                                    }
                                }
                                .buttonStyle(.ppPrimary)
                                .disabled(authViewModel.isLoading || !isFormValid)
                                
                                HStack {
                                    Button(isRegistering ? "Sign In" : "Register") {
                                        withAnimation {
                                            isRegistering.toggle()
                                            authViewModel.errorMessage = nil
                                        }
                                    }
                                    
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    
                                    Button("Back") {
                                        withAnimation {
                                            showEmailForm = false
                                            authViewModel.errorMessage = nil
                                        }
                                    }
                                }
                                .font(.subheadline)
                                .foregroundColor(.ppPurple)
                            }
                            .padding(.horizontal, 32)
                            .transition(.move(edge: .trailing))
                        }
                        
                        Spacer()
                    }
                }
            }
            
            if authViewModel.isLoading {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    )
                    .zIndex(1)
            }
        }
        .onAppear {
            // Auto-login with Face ID if available and user hasn't just logged out
            if authViewModel.canUseBiometricLogin && !authViewModel.hasLoggedOut {
                Task {
                    await authViewModel.loginWithBiometrics()
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        if isRegistering {
            return !email.isEmpty && !password.isEmpty && !name.isEmpty
        }
        return !email.isEmpty && !password.isEmpty
    }
}

#Preview {
    LoginView()
        .environment(AuthViewModel())
}
