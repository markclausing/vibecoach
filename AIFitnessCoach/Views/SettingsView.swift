import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var notificationManager: NotificationManager

    var body: some View {
        Form {
            Section(header: Text("Notificaties")) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Proactieve AI-coach")
                            .font(.headline)
                        Text("Ontvang notificaties zodra je een Strava training voltooit.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    if notificationManager.isAuthorized {
                        Text("AAN")
                            .foregroundColor(.green)
                            .fontWeight(.bold)
                    } else {
                        Button("Aanzetten") {
                            notificationManager.requestAuthorization()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .navigationTitle("Instellingen")
    }
}
