import SwiftUI

struct SettingsView: View {
    @StateObject private var notificationManager = NotificationManager.shared

    var body: some View {
        Form {
            Section(header: Text("Notificaties")) {
                HStack {
                    Text("Push Notificaties")
                    Spacer()
                    if notificationManager.hasPermission {
                        Text("Aan")
                            .foregroundColor(.secondary)
                    } else {
                        Button("Zet aan") {
                            Task {
                                await notificationManager.requestPermission()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Instellingen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
