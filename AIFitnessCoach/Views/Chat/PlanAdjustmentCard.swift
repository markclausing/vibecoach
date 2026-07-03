import SwiftUI

// MARK: PlanAdjustmentCard

struct PlanAdjustment: Identifiable {
    let id = UUID()
    let dayAbbr: String
    let dayNum: Int
    let original: String
    let replacement: String
}

struct PlanAdjustmentCard: View {
    let adjustments: [PlanAdjustment]
    let accentColor: Color
    var onApply: () -> Void
    var onView: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundColor(accentColor)
                    Text("AANPASSING IN JE PLAN")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.secondary).kerning(0.5)
                }
                Spacer()
                Text("Voorstel")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            Divider().padding(.horizontal, 14)

            // Adjustment rows
            VStack(spacing: 14) {
                ForEach(adjustments) { adj in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Text(adj.dayAbbr)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text("\(adj.dayNum)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .frame(width: 30)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(adj.original)
                                .font(.subheadline)
                                .strikethrough(true, color: .secondary)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(accentColor)
                                Text(adj.replacement)
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)

            Divider().padding(.horizontal, 14)

            // Action buttons
            HStack(spacing: 10) {
                Button(action: onApply) {
                    Text("Toepassen")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button(action: onView) {
                    HStack(spacing: 4) {
                        Text("Bekijk")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .padding(.vertical, 14).padding(.horizontal, 20)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator), lineWidth: 1))
                }
            }
            .padding(14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(.label).opacity(0.06), radius: 8, x: 0, y: 2)
    }
}
