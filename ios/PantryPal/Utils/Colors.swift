import SwiftUI

extension Color {
    // MARK: - PantryPal Color Palette
    
    /// Rebecca Purple - Primary accent #5941A9
    static let ppPurple = Color(red: 89/255, green: 65/255, blue: 169/255)
    
    /// Orange - Secondary accent color #F3A712
    static let ppOrange = Color(red: 243/255, green: 167/255, blue: 18/255)
    
    /// Sage Green - Tertiary/success color #6D9F71
    static let ppGreen = Color(red: 109/255, green: 159/255, blue: 113/255)
    
    /// White #FFFFFF
    static let ppWhite = Color.white
    
    // MARK: - Semantic Colors
    
    /// Primary brand color (Purple)
    static let ppPrimary = ppPurple
    
    /// Secondary brand color (Orange)
    static let ppSecondary = ppOrange
    
    /// Tertiary brand color (Green)
    static let ppTertiary = ppGreen
    
    /// Success/fresh items (Green)
    static let ppSuccess = ppGreen
    
    /// Warning - expiring soon (Orange)
    static let ppWarning = ppOrange
    
    /// Danger - expired items (darker shade)
    static let ppDanger = Color(red: 200/255, green: 60/255, blue: 60/255)
    
    /// Background colors
    static let ppBackground = Color(UIColor.systemBackground)
    static let ppSecondaryBackground = Color(UIColor.secondarySystemBackground)
    
    /// Text colors
    static let ppText = Color(UIColor.label)
    static let ppSecondaryText = Color(UIColor.secondaryLabel)
}

// MARK: - Gradient Extensions

extension LinearGradient {
    /// Primary gradient (Purple to Orange)
    static let ppPrimaryGradient = LinearGradient(
        colors: [.ppPurple, .ppOrange],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Fresh gradient (Green to Purple)
    static let ppFreshGradient = LinearGradient(
        colors: [.ppGreen, .ppPurple],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    /// Full palette gradient
    static let ppFullGradient = LinearGradient(
        colors: [.ppPurple, .ppOrange, .ppGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - View Modifiers

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.ppPrimary)
            .foregroundColor(.white)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.ppSecondary)
            .foregroundColor(.white)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var ppPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var ppSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
