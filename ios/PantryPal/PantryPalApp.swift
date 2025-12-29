import SwiftUI
import SwiftData

@main
struct PantryPalApp: App {
    @State private var authViewModel = AuthViewModel()
    @StateObject private var notificationService = NotificationService.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SDProduct.self,
            SDInventoryItem.self,
            SDLocation.self,
            SDPendingAction.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            SplashView()
                .environment(authViewModel)
                .environmentObject(notificationService)
                .modelContainer(sharedModelContainer)
                .task {
                    // Request notification permission on first launch
                    _ = await notificationService.requestAuthorization()
                }
        }
    }
}

// App Delegate for handling remote notifications
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.shared.handleDeviceToken(deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationService.shared.handleRegistrationError(error)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Handle notifications when app is in foreground
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        // Handle notification tap - could navigate to specific item
        print("Notification tapped: \(userInfo)")
        completionHandler()
    }
}

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    var body: some View {
        @Bindable var authViewModel = authViewModel
        Group {
            if authViewModel.isAuthenticated {
                if authViewModel.showHouseholdSetup {
                    HouseholdSetupView()
                } else {
                    MainTabView()
                }
            } else {
                LoginView()
            }
        }
        .alert("Enable \(authViewModel.biometricName)?", isPresented: $authViewModel.showBiometricEnablePrompt) {
            Button("Enable") {
                authViewModel.enableBiometricLogin()
            }
            Button("Not Now", role: .cancel) {
                authViewModel.declineBiometricLogin()
            }
        } message: {
            Text("Would you like to use \(authViewModel.biometricName) to sign in faster next time?")
        }
    }
}

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    
    var body: some View {
        TabView {
            InventoryListView()
                .tabItem {
                    Label("Pantry", systemImage: "refrigerator")
                }
            
            CheckoutView()
                .tabItem {
                    Label("Checkout", systemImage: "barcode.viewfinder")
                }
        }
        .tint(.ppPurple)
    }
}

#Preview {
    ContentView()
        .environment(AuthViewModel())
}
