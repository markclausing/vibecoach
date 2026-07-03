import SwiftUI

/// Section in `WorkoutDetailView` with structured nutrition and hydration information.
struct WorkoutFuelingSectionView: View {
    let plan: WorkoutFuelingPlan

    private var interval: NutritionService.FuelingInterval {
        NutritionService.intervalBreakdown(plan: plan, every: 15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voeding & Hydratatie")
                .font(.headline)

            // Total overview
            VStack(spacing: 12) {
                InfoRowView(icon: "flame.fill",
                            title: "Verbranding",
                            value: "~\(Int(plan.totalCaloriesBurned.rounded())) kcal")
                InfoRowView(icon: "drop.fill",
                            title: "Totaal vocht",
                            value: "\(Int(plan.fluidMl.rounded())) ml")
                    .foregroundStyle(.blue)
                InfoRowView(icon: "leaf.fill",
                            title: "Totaal koolhydraten",
                            value: "\(Int(plan.carbsGram.rounded())) g")
                    .foregroundStyle(.green)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            // Interval breakdown
            VStack(alignment: .leading, spacing: 8) {
                Label("Per \(interval.intervalMinutes) minuten", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 12) {
                    intervalPill(
                        icon: "drop.fill",
                        value: "~\(Int(interval.fluidMl.rounded())) ml",
                        label: "drinken",
                        color: .blue
                    )
                    intervalPill(
                        icon: "leaf.fill",
                        value: "~\(Int(interval.carbsGram.rounded())) g",
                        label: "koolhydraten",
                        color: .green
                    )
                }

                // Timing tips
                // Epic #37 story 37.1c: phase + tips localized. Numbers are pre-formatted into
                // Strings and interpolated as %@; the optional carbs clause is its own catalog key.
                VStack(alignment: .leading, spacing: 4) {
                    timingRow(phase: "Voor", tip: String(localized: "Drink 400–600 ml water 2 uur voor de start"))
                    timingRow(phase: "Tijdens", tip: {
                        let fluidStr = "\(Int(interval.fluidMl.rounded()))"
                        var tip = String(localized: "Drink elk kwartier \(fluidStr) ml")
                        if plan.carbsGram > 20 {
                            let carbsStr = "\(Int(interval.carbsGram.rounded() * 2))"
                            tip += String(localized: "; neem elke 30 min een gelletje of \(carbsStr) g koolhydraten")
                        }
                        return tip
                    }())
                    timingRow(phase: "Na", tip: {
                        let kcalStr = "\(Int((plan.totalCaloriesBurned * 0.25).rounded()))"
                        return String(localized: "Herstel met \(kcalStr) kcal (eiwitten + koolhydraten) binnen 30 min")
                    }())
                }
                .padding(.top, 4)
            }
        }
    }

    private func intervalPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(color)
                Text(value).fontWeight(.semibold)
            }
            .font(.subheadline)
            // Epic #37 story 37.1c: label/phase are Dutch literals -> catalog; value is data.
            Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func timingRow(phase: String, tip: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(LocalizedStringKey(phase))
                .font(.caption.weight(.semibold))
                .frame(width: 46, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(tip)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
