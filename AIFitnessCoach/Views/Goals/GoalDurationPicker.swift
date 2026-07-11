import SwiftUI

/// Epic #72 story 72.5: duration input (hours:minutes) for a target finish time.
/// Replaces the old `.hourAndMinute` DatePicker, which rendered the duration as a
/// time-of-day ("4:00 AM" on 12-hour locales).
struct GoalDurationPicker: View {
    let label: LocalizedStringKey
    @Binding var hours: Int
    @Binding var minutes: Int

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(label)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(format: "%d:%02d", hours, minutes))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("GoalDurationPicker")

            if isExpanded {
                // iOS Timer-app pattern: two wheel columns with a trailing unit label each.
                HStack(spacing: 4) {
                    Picker("", selection: $hours) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text("\(hour)").tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                    Text("uur")
                        .foregroundStyle(.secondary)

                    Picker("", selection: $minutes) {
                        ForEach(0..<60, id: \.self) { minute in
                            Text("\(minute)").tag(minute)
                        }
                    }
                    .pickerStyle(.wheel)
                    Text("min")
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
                .labelsHidden()
            }
        }
    }
}
