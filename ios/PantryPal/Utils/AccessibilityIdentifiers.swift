import Foundation

/// Centralized accessibility identifiers for UI testing
enum AccessibilityIdentifiers {
    
    // MARK: - Login/Onboarding
    enum Login {
        static let signInWithAppleButton = "login.signInWithApple"
        static let continueWithEmailButton = "login.continueWithEmail"
        static let emailField = "login.emailField"
        static let passwordField = "login.passwordField"
        static let loginButton = "login.loginButton"
        static let registerButton = "login.registerButton"
        static let firstNameField = "login.firstNameField"
        static let lastNameField = "login.lastNameField"
    }
    
    enum Onboarding {
        static let startButton = "onboarding.startButton"
        static let joinButton = "onboarding.joinButton"
        static let skipButton = "onboarding.skipButton"
        static let inviteCodeField = "onboarding.inviteCodeField"
        static let scanQRButton = "onboarding.scanQRButton"
    }
    
    // MARK: - Inventory/Pantry
    enum Inventory {
        static let list = "inventory.list"
        static let addButton = "inventory.addButton"
        static let scanButton = "inventory.scanButton"
        static let searchField = "inventory.searchField"
        static let emptyState = "inventory.emptyState"
        
        // Row identifiers use item ID
        static func row(id: String) -> String {
            return "inventory.row.\(id)"
        }
        
        static func incrementButton(id: String) -> String {
            return "inventory.increment.\(id)"
        }
        
        static func decrementButton(id: String) -> String {
            return "inventory.decrement.\(id)"
        }
        
        static func quantityLabel(id: String) -> String {
            return "inventory.quantity.\(id)"
        }
    }
    
    // MARK: - Scanner
    enum Scanner {
        static let container = "scanner.container"
        static let scanAgainButton = "scanner.scanAgain"
        static let addButton = "scanner.addButton"
        static let increaseQuantityButton = "scanner.increaseQuantity"
        static let locationPicker = "scanner.locationPicker"
        static let closeButton = "scanner.close"
        
        // Debug/Test mode
        static let debugInjectButton = "scanner.debug.inject"
        static let debugUPCField = "scanner.debug.upcField"
    }
    
    // MARK: - Add Custom Item
    enum AddItem {
        static let sheet = "addItem.sheet"
        static let nameField = "addItem.nameField"
        static let brandField = "addItem.brandField"
        static let upcField = "addItem.upcField"
        static let locationPicker = "addItem.locationPicker"
        static let saveButton = "addItem.saveButton"
        static let cancelButton = "addItem.cancelButton"
    }
    
    // MARK: - Checkout
    enum Checkout {
        static let tabButton = "checkout.tabButton"
        static let scanButton = "checkout.scanButton"
        static let historyList = "checkout.historyList"
        static let emptyState = "checkout.emptyState"
        
        static func historyRow(id: String) -> String {
            return "checkout.history.\(id)"
        }
    }
    
    // MARK: - Grocery
    enum Grocery {
        static let tabButton = "grocery.tabButton"
        static let addField = "grocery.addField"
        static let addButton = "grocery.addButton"
        static let list = "grocery.list"
        static let emptyState = "grocery.emptyState"
        
        static func row(id: String) -> String {
            return "grocery.row.\(id)"
        }
        
        static func checkButton(id: String) -> String {
            return "grocery.check.\(id)"
        }
    }
    
    // MARK: - Settings
    enum Settings {
        static let tabButton = "settings.tabButton"
        static let signOutButton = "settings.signOut"
        static let householdSharingButton = "settings.householdSharing"
        static let premiumButton = "settings.premium"
        static let appLockToggle = "settings.appLockToggle"
        static let accountSection = "settings.accountSection"
    }
    
    // MARK: - Household
    enum Household {
        static let generateInviteButton = "household.generateInvite"
        static let inviteCodeLabel = "household.inviteCode"
        static let qrCodeImage = "household.qrCode"
        static let membersList = "household.membersList"
        
        static func memberRow(id: String) -> String {
            return "household.member.\(id)"
        }
    }
    
    // MARK: - Paywall
    enum Paywall {
        static let container = "paywall.container"
        static let upgradeButton = "paywall.upgradeButton"
        static let dismissButton = "paywall.dismiss"
        static let debugSimulateButton = "paywall.debug.simulate"
    }
    
    // MARK: - Common
    enum Common {
        static let loadingIndicator = "common.loading"
        static let errorAlert = "common.errorAlert"
        static let successToast = "common.successToast"
        static let pullToRefresh = "common.pullToRefresh"
    }
}
