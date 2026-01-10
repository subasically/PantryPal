import XCTest

struct SystemAlertsHelper {
    /// sets up a monitor for system alerts (Notifications, Location, etc) and dismisses them.
    static func handleSystemAlerts(monitorToken: inout NSObjectProtocol?) {
        monitorToken = XCTestCase().addUIInterruptionMonitor(withDescription: "System Alerts") { alert in
            let allowButtons = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Allow' OR label CONTAINS[c] 'OK' OR label CONTAINS[c] 'Enable'"))
            if allowButtons.count > 0 {
                allowButtons.firstMatch.tap()
                return true
            }
            
            // Fallback for "Don't Allow" if we want to be strict, but usually we want Allow.
            // For now, just tapping the first button is risky, so searching for positive keywords.
            
            return false
        }
    }
    
    /// Explicitly taps "Allow" if a system alert is present currently.
    /// This is sometimes needed because interruption monitors are flaky.
    static func dismissIfPresent(app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alerts = springboard.alerts
        if alerts.count > 0 {
            let allowButton = alerts.buttons["Allow"]
            if allowButton.exists {
                allowButton.tap()
            }
            
            let okButton = alerts.buttons["OK"]
            if okButton.exists {
                okButton.tap()
            }
        }
    }
}
