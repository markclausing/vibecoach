import SwiftUI

// MARK: CoachV2HeaderView

struct CoachV2HeaderView: View {
    let phaseLabel: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundColor(accentColor)
                Circle()
                    .fill(Color.green)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color(.secondarySystemBackground), lineWidth: 2))
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Coach")
                    .font(.title2).fontWeight(.bold)
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(phaseLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("CoachView")
    }
}
