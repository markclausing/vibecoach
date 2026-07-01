import SwiftUI
import Charts

// MARK: - SPRINT 12.2: TRIMP Explainer Card
struct TRIMPExplainerCard: View {
    /// Collapsed by default — the user opens it when they want to read the details.
    @State private var isExpanded: Bool = false
    @State private var durationMinutes: Double = 60
    @State private var intensityZone: Double = 2.0 // 1 to 5

    // Simple Banister mapping based on Zone (Zone 2 = slight heart rate increase, Zone 5 = max)
    // Z1 ~ 60%, Z2 ~ 70%, Z3 ~ 80%, Z4 ~ 90%, Z5 ~ 95% deltaHR
    private var simulatedDeltaHR: Double {
        switch Int(intensityZone) {
        case 1: return 0.60
        case 2: return 0.70
        case 3: return 0.80
        case 4: return 0.90
        case 5: return 0.95
        default: return 0.70
        }
    }

    private var calculatedTRIMP: Double {
        return durationMinutes * simulatedDeltaHR * 0.64 * exp(1.92 * simulatedDeltaHR)
    }

    struct ExplainerPoint: Identifiable {
        let id = UUID()
        let zone: Int
        let trimp: Double
    }

    private var curveData: [ExplainerPoint] {
        var points: [ExplainerPoint] = []
        for z in 1...5 {
            let hr: Double
            switch z {
            case 1: hr = 0.60; case 2: hr = 0.70; case 3: hr = 0.80; case 4: hr = 0.90; case 5: hr = 0.95; default: hr = 0.70
            }
            let trimpValue = durationMinutes * hr * 0.64 * exp(1.92 * hr)
            points.append(ExplainerPoint(zone: z, trimp: trimpValue))
        }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, tap to expand/collapse
            Button(action: { withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wat is TRIMP?")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("TRIMP meet de échte fysiologische impact van je training.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
            Divider()
            VStack(alignment: .leading, spacing: 16) {
            // Interactive sliders
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Duur: \(Int(durationMinutes)) min")
                        .font(.caption)
                        .fontWeight(.bold)
                    Slider(value: $durationMinutes, in: 10...180, step: 5)
                        .accentColor(.blue)
                }

                VStack(alignment: .leading) {
                    Text("Intensiteit: Zone \(Int(intensityZone))")
                        .font(.caption)
                        .fontWeight(.bold)
                    Slider(value: $intensityZone, in: 1...5, step: 1)
                        .accentColor(.red)
                }
            }
            .padding(.vertical, 8)

            // Dynamic score & chart
            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    Text("TRIMP Score")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(calculatedTRIMP))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(calculatedTRIMP > 100 ? .red : (calculatedTRIMP > 60 ? .orange : .green))
                }

                Spacer()

                Chart(curveData) { point in
                    LineMark(
                        x: .value("Zone", point.zone),
                        y: .value("TRIMP", point.trimp)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.red.gradient)

                    PointMark(
                        x: .value("Zone", point.zone),
                        y: .value("TRIMP", point.trimp)
                    )
                    .symbolSize(point.zone == Int(intensityZone) ? 150 : 50)
                    .foregroundStyle(point.zone == Int(intensityZone) ? .red : .gray)
                }
                .frame(width: 120, height: 60)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }

            Divider()

            // Fixed explanation text
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: "clock.fill").foregroundColor(.blue).frame(width: 24)
                    Text("**Volume:** De basis is de tijd die je sport.").font(.caption)
                }
                HStack(alignment: .top) {
                    Image(systemName: "heart.fill").foregroundColor(.red).frame(width: 24)
                    Text("**Intensiteit:** Je hartslag gemeten tegen je persoonlijke maximum.").font(.caption)
                }
                HStack(alignment: .top) {
                    Image(systemName: "flame.fill").foregroundColor(.orange).frame(width: 24)
                    Text("**De Prijs:** In het rood (Zone 4-5) trainen scoort exponentieel hoger door verzuring en spierschade.").font(.caption)
                }
            }
            .padding(.top, 4)
        }
        .padding([.horizontal, .bottom])
        } // end if isExpanded
        }
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
