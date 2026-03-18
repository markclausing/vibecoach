import Foundation
import UserNotifications
import UIKit

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var hasPermission = false

    private init() {
        Task {
            await checkPermission()
        }
    }

    func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.hasPermission = settings.authorizationStatus == .authorized
    }

    func requestPermission() async {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            self.hasPermission = granted

            if granted {
                print("APNs permission granted.")
                // Registreer voor remote notifications op de main thread
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                print("APNs permission denied.")
            }
        } catch {
            print("Error requesting APNs permission: \(error.localizedDescription)")
        }
    }
}
