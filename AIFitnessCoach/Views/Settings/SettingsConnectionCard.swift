import SwiftUI

// Epic #65 story 65.5: split out of SettingsView.swift (§5 file-split). Pure move —
// no semantic changes; access relaxed private -> internal only where the split
// requires it (listed in the PR body).

struct SettingsConnectionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isConnected: Bool
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(accentColor)
                }
                Spacer()
                Circle()
                    .fill(isConnected ? Color.green : Color(.systemGray4))
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color(.label).opacity(0.05), radius: 6, x: 0, y: 2)
    }
}
