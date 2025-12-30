import SwiftUI
import SwiftData

@main
struct PantryPalApp: App {
    @State private var authViewModel = AuthViewModel()
    @StateObject private var notificationService = NotificationService.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SDProduct.self,
            SDInventoryItem.self,
            SDLocation.self,
            SDPendingAction.self,
            SDGroceryItem.self,
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
            ZStack {
                SplashView()
                    .environment(authViewModel)
                    .environmentObject(notificationService)
                    .modelContainer(sharedModelContainer)
                    .task {
                        // Request notification permission on first launch
                        _ = await notificationService.requestAuthorization()
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        authViewModel.handleScenePhaseChange(newPhase)
                    }
                    .fullScreenCover(isPresented: $authViewModel.isAppLocked) {
                        LockOverlayView(authViewModel: authViewModel)
                    }
                
                // Global toast overlay
                ToastHostView()
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
            
            GroceryListView()
                .tabItem {
                    Label("Grocery", systemImage: "cart")
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

struct LockOverlayView: View {
    var authViewModel: AuthViewModel
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.ppPurple)
                
                Text("PantryPal Locked")
                    .font(.title)
                    .fontWeight(.bold)
                
                Button {
                    Task {
                        await authViewModel.unlockApp()
                    }
                } label: {
                    Label("Unlock with \(authViewModel.biometricName)", systemImage: authViewModel.biometricIcon)
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: 280)
                        .background(Color.ppPurple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .onAppear {
            // Auto-prompt on appear
            Task {
                await authViewModel.unlockApp()
            }
        }
    }
}
