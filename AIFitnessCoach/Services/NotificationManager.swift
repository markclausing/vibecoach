import Foundation
import UserNotifications
import UIKit

/// Beheert de aanvragen voor Push Notificaties.
@MainActor
class NotificationManager: ObservableObject {
    @Published var isAuthorized: Bool = false

    /// Controleert de huidige status van de notificatie-permissies.
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    /// Vraagt toestemming voor push notificaties.
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if granted {
                    // Start de registratie bij APNs (hiermee wordt de didRegister delegate afgevuurd)
                    UIApplication.shared.registerForRemoteNotifications()
                } else if let error = error {
                    print("⚠️ Fout bij aanvragen notificatie permissies: \(error.localizedDescription)")
                }
            }
        }
    }
}
