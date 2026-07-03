import SwiftUI

// MARK: SuggestionChipsView

struct SuggestionChipsView: View {
    let suggestions: [String]
    var onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OF VRAAG")
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(.secondary).kerning(0.5)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        // Epic #37 story 37.1c: chips are Dutch literals -> catalog. Send the
                        // localized text so the sent message matches the displayed chip.
                        Button { onTap(String(localized: String.LocalizationValue(suggestion))) } label: {
                            Text(LocalizedStringKey(suggestion))
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Color(.systemBackground))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }
}
