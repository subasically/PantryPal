import Foundation
import UserNotifications
import UIKit

@MainActor
final class NotificationService: ObservableObject {
    nonisolated static let shared = NotificationService()
    
    @Published var isAuthorized = false
    @Published var deviceToken: String?
    var currentHousehold: Household?
    
    private nonisolated init() {
        Task { @MainActor in
            await checkAuthorization()
        }
    }
    
    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await checkAuthorization()
            
            // Register for remote notifications if granted
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }
    
    // MARK: - Remote Notification Registration
    
    func handleDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = tokenString
        print("Device token: \(tokenString)")
        
        // Register token with server
        Task {
            await registerTokenWithServer(tokenString)
        }
    }
    
    func handleRegistrationError(_ error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
    
    private func registerTokenWithServer(_ token: String) async {
        guard let authToken = APIService.shared.currentToken else {
            print("No auth token, skipping device token registration")
            return
        }
        
        do {
            let baseURL = APIService.shared.currentBaseURL
            var request = URLRequest(url: URL(string: "\(baseURL)/notifications/register")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(["token": token, "platform": "ios"])
            
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Device token registered with server")
            }
        } catch {
            print("Failed to register device token with server: \(error)")
        }
    }
    
    func unregisterTokenFromServer() async {
        guard let token = deviceToken,
              let authToken = APIService.shared.currentToken else { return }
        
        do {
            let baseURL = APIService.shared.currentBaseURL
            var request = URLRequest(url: URL(string: "\(baseURL)/notifications/unregister")!)
            request.httpMethod = "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(["token": token])
            
            let (_, _) = try await URLSession.shared.data(for: request)
            print("Device token unregistered from server")
        } catch {
            print("Failed to unregister device token: \(error)")
        }
    }
    
    // MARK: - Expiration Notifications
    
    func scheduleExpirationNotifications(for items: [InventoryItem]) async {
        // Premium-only feature
        guard isAuthorized,
              let household = currentHousehold,
              household.isPremiumActive else {
            print("⚠️ [NotificationService] Expiration notifications require Premium")
            return
        }
        
        // Remove all existing expiration notifications
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        let expirationIds = requests.filter { $0.identifier.hasPrefix("expiration_") }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: expirationIds)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for item in items {
            guard let expDateStr = item.expirationDate,
                  let expDate = dateFormatter.date(from: expDateStr) else { continue }
            
            let now = Date()
            let calendar = Calendar.current
            
            // Skip if already expired
            if expDate < now { continue }
            
            // Schedule notification for 7 days before expiration (Premium)
            if let notifyDate = calendar.date(byAdding: .day, value: -7, to: expDate), notifyDate > now {
                await scheduleNotification(
                    id: "expiration_7d_\(item.id)",
                    title: "Item Expiring Soon",
                    body: "\(item.displayName) will expire in 7 days",
                    date: notifyDate
                )
            }
            
            // Schedule notification for 3 days before expiration (Premium)
            if let notifyDate = calendar.date(byAdding: .day, value: -3, to: expDate), notifyDate > now {
                await scheduleNotification(
                    id: "expiration_3d_\(item.id)",
                    title: "Item Expiring Soon",
                    body: "\(item.displayName) will expire in 3 days",
                    date: notifyDate
                )
            }
            
            // Schedule notification for 1 day before expiration (Premium)
            if let notifyDate = calendar.date(byAdding: .day, value: -1, to: expDate), notifyDate > now {
                await scheduleNotification(
                    id: "expiration_1d_\(item.id)",
                    title: "Item Expiring Tomorrow",
                    body: "\(item.displayName) will expire tomorrow!",
                    date: notifyDate
                )
            }
            
            // Schedule notification on expiration day
            await scheduleNotification(
                id: "expiration_0d_\(item.id)",
                title: "Item Expired",
                body: "\(item.displayName) expires today!",
                date: expDate
            )
        }
    }
    
    private func scheduleNotification(id: String, title: String, body: String, date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Schedule for 9 AM on the notification date
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }
    
    // MARK: - Checkout Notifications
    
    func sendCheckoutNotification(itemName: String, remainingQuantity: Int) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Item Checked Out"
        
        if remainingQuantity == 0 {
            content.body = "\(itemName) is now out of stock!"
            content.sound = .default
        } else if remainingQuantity <= 2 {
            content.body = "\(itemName) is running low (\(remainingQuantity) left)"
            content.sound = .default
        } else {
            content.body = "\(itemName) checked out. \(remainingQuantity) remaining."
        }
        
        let request = UNNotificationRequest(
            identifier: "checkout_\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
    
    // MARK: - Low Stock Notifications
    
    func checkLowStockItems(_ items: [InventoryItem], threshold: Int = 2) async {
        guard isAuthorized else { return }
        
        let lowStockItems = items.filter { $0.quantity <= threshold }
        
        if lowStockItems.isEmpty { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Low Stock Alert"
        
        if lowStockItems.count == 1 {
            content.body = "\(lowStockItems[0].displayName) is running low"
        } else {
            content.body = "\(lowStockItems.count) items are running low"
        }
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "lowstock_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Clear All Notifications
    
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
