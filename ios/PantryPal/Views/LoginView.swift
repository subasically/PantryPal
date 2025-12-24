import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isRegistering = false
    
    var body: some View {
        @Bindable var authViewModel = authViewModel
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo/Title
                    VStack(spacing: 8) {
                        Image(systemName: "refrigerator.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(LinearGradient.ppPrimaryGradient)
                        
                        Text("PantryPal")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.ppPurple)
                        
                        Text("Track your pantry inventory")
                            .foregroundColor(.ppSecondaryText)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                    
                    // Apple Sign In
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task {
                            await authViewModel.handleAppleSignIn(result: result)
                        }
                    }
                    .signInWithAppleButtonStyle(.whiteOutline)
                    .frame(height: 50)
                    .padding(.horizontal)
                    
                    // Biometric Login Button (if available and enabled)
                    if !isRegistering && authViewModel.canUseBiometricLogin {
                        Button(action: {
                            Task {
                                await authViewModel.loginWithBiometrics()
                            }
                        }) {
                            HStack {
                                Image(systemName: authViewModel.biometricIcon)
                                    .font(.title2)
                                Text("Sign in with \(authViewModel.biometricName)")
                            }
                        }
                        .buttonStyle(.ppPrimary)
                        .padding(.horizontal)
                        
                        HStack {
                            Rectangle()
                                .fill(Color.ppSecondaryText.opacity(0.3))
                                .frame(height: 1)
                            Text("or")
                                .foregroundColor(.ppSecondaryText)
                                .font(.caption)
                            Rectangle()
                                .fill(Color.ppSecondaryText.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 40)
                    }
                    
                    // Form
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
                    .padding(.horizontal)
                    
                    // Error message
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Buttons
                    VStack(spacing: 12) {
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
                        
                        Button(action: {
                            withAnimation {
                                isRegistering.toggle()
                                authViewModel.errorMessage = nil
                            }
                        }) {
                            Text(isRegistering ? "Already have an account? Sign In" : "Don't have an account? Register")
                                .foregroundColor(.ppPurple)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
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
