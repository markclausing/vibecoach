import Foundation
import UIKit
import UserNotifications

/// Verantwoordelijk voor het ontvangen van push notificatie events, zoals de APNs device token.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Stel de delegate in voor het ontvangen van push-notificaties terwijl de app actief is.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Converteer de token data naar een hexadecimale string, vereist door de Node APNs package
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()

        print("✅ [APNs] Succesvol geregistreerd voor Push Notificaties.")
        print("📱 Device Token: \(token)")
        print("ℹ️ Kopieer deze token naar je TEST_DEVICE_TOKEN in de backend .env voor lokaal testen.")

        // In een later stadium zouden we deze token veilig (bijv. met Keychain) opslaan
        // en meesturen met onze web-requests naar de eigen backend API.
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ [APNs] Fout bij registreren voor Push Notificaties: \(error.localizedDescription)")
    }

    // Optioneel: Laat notificaties zien zelfs als de app actief is (in de voorgrond)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
