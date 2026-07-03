import SwiftUI

// Epic #65 story 65.5: split out of SettingsView.swift (§5 file-split). Pure move —
// no semantic changes; access relaxed private -> internal only where the split
// requires it (listed in the PR body).

struct SettingsRowV2: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String?
    var value: String?
    var hasChevron: Bool = false
    var isLocked: Bool = false
    var isWarning: Bool = false
    var showHealthKitBadge: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isWarning ? Color.orange.opacity(0.12) : iconColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isWarning ? .orange : iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                // Epic #37 story 37.1c: `title`/`subtitle` are `String` (call sites pass literals
                // and computed values), so wrap them in `LocalizedStringKey` to resolve via the
                // String Catalog at runtime. Brand names not in the catalog fall back unchanged.
                // `value` stays verbatim — it's dynamic data (e.g. "76.0 kg").
                Text(LocalizedStringKey(title))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isWarning ? .orange : .primary)
                if let sub = subtitle {
                    Text(LocalizedStringKey(sub))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let val = value {
                Text(val)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            if showHealthKitBadge {
                Image(systemName: "applewatch")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(Color(.systemGray3))
            } else if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(.systemGray3))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(isWarning ? Color.orange.opacity(0.05) : Color.clear)
    }
}
