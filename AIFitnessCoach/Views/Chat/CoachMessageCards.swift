import SwiftUI

// MARK: CoachTextCard

struct CoachTextCard: View {
    let text: String
    let accentColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            coachAvatar(accentColor)
            VStack(alignment: .leading, spacing: 8) {
                Text("KORT")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(accentColor).kerning(0.8)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color(.label).opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }
}

// MARK: CoachInsightCard

struct CoachInsightCard: View {
    let insights: [String]
    let accentColor: Color

    @State private var isExpanded = false

    private var visibleCount: Int { isExpanded ? insights.count : min(1, insights.count) }
    private var hiddenCount: Int { max(0, insights.count - 1) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            coachAvatar(accentColor)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption).foregroundColor(accentColor)
                    Text("WAT IK ZIE")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.secondary).kerning(0.8)
                }
                ForEach(Array(insights.prefix(visibleCount).enumerated()), id: \.offset) { _, insight in
                    Text(insight)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hiddenCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Minder tonen" : "Meer uitleg (\(hiddenCount))")
                                .font(.caption).fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color(.label).opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }
}

// MARK: Shared coach avatar helper

private func coachAvatar(_ accentColor: Color) -> some View {
    ZStack {
        Circle()
            .fill(accentColor.opacity(0.10))
            .frame(width: 30, height: 30)
        Image(systemName: "bubble.left.fill")
            .font(.system(size: 12))
            .foregroundColor(accentColor)
    }
    .padding(.top, 14)
}
