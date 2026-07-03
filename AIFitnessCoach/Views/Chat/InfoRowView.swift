import SwiftUI

/// Reusable row for information in the WorkoutDetailView
struct InfoRowView: View {
    let icon: String
    let title: String
    let value: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(themeManager.primaryAccentColor.opacity(0.75))
            // Epic #37 story 37.1c: title is a Dutch literal -> catalog; value is data.
            Text(LocalizedStringKey(title))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
