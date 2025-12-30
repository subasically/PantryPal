import SwiftUI

/// Standardized text field component matching Apple HIG guidelines
/// - Minimum 44pt touch target height
/// - Consistent padding and styling
/// - Supports Dynamic Type
struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrectionDisabled: Bool = false
    
    var body: some View {
        TextField(placeholder, text: $text)
            .padding()
            .frame(minHeight: 44)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(autocorrectionDisabled)
    }
}

/// Standardized secure field component matching Apple HIG guidelines
struct AppSecureField: View {
    let placeholder: String
    @Binding var text: String
    var textContentType: UITextContentType? = nil
    
    var body: some View {
        SecureField(placeholder, text: $text)
            .padding()
            .frame(minHeight: 44)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .textContentType(textContentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
    }
}

// MARK: - Previews

#Preview("AppTextField") {
    VStack(spacing: 16) {
        AppTextField(
            placeholder: "Email",
            text: .constant(""),
            keyboardType: .emailAddress,
            textContentType: .emailAddress,
            autocapitalization: .never,
            autocorrectionDisabled: true
        )
        
        AppTextField(
            placeholder: "Name",
            text: .constant("John Doe"),
            textContentType: .name
        )
        
        AppSecureField(
            placeholder: "Password",
            text: .constant(""),
            textContentType: .password
        )
    }
    .padding()
}
