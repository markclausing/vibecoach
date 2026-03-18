import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Zorg dat we delegate zijn van het notification center om in-app (foreground) notificaties af te handelen
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // Wordt aangeroepen wanneer de app succesvol een APNs token heeft ontvangen
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        print("✅ APNs Device Token ontvangen!")
        print("Kopieer dit token naar je backend .env bestand onder TEST_DEVICE_TOKEN:")
        print("--------------------------------------------------")
        print(token)
        print("--------------------------------------------------")
    }

    // Wordt aangeroepen als er iets misgaat bij het registreren voor APNs
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Fout bij registreren voor Push Notifications: \(error.localizedDescription)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Deze methode zorgt ervoor dat notificaties ook getoond worden als de app op de voorgrond (foreground) open is.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {

        print("🔔 Notificatie ontvangen in de voorgrond: \(notification.request.content.title)")

        // Toon de notificatie als een banner (en speel geluid af)
        completionHandler([.banner, .sound])
    }
}
