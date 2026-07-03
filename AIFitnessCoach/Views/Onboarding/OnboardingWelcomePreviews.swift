import SwiftUI

// Epic #65 story 65.5: split out of OnboardingView.swift (§5 file-split). Pure move — no
// semantic changes; access relaxed private -> internal only where the split
// requires it (listed in the PR body).

// MARK: - Step 1: Welcome visual

/// Large rounded 'brand mark' with a waveform icon in moss green, followed
/// by the uppercase brand word "VIBECOACH". Matches the prototype.
struct WelcomeBrandMark: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(themeManager.primaryAccentColor)
                    .frame(width: 128, height: 128)
                    .shadow(color: themeManager.primaryAccentColor.opacity(0.35), radius: 20, x: 0, y: 10)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("VIBECOACH")
                .font(.subheadline)
                .fontWeight(.semibold)
                .kerning(3.0)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Step 2: Two layers preview

/// Two preview cards side by side: on the left the Vibe Score (ring), on the right the
/// TRIMP trend (bars). Same card style as the Dashboard.
struct TwoLayersPreview: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            VibeScorePreviewCard(accent: themeManager.primaryAccentColor)
            TRIMPPreviewCard(accent: themeManager.primaryAccentColor)
        }
        .padding(.horizontal, 24)
    }
}

private struct VibeScorePreviewCard: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VIBE SCORE")
                .font(.caption2)
                .fontWeight(.semibold)
                .kerning(1.0)
                .foregroundColor(.secondary)

            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 8)
                    .frame(width: 86, height: 86)

                Circle()
                    .trim(from: 0, to: 0.76)
                    .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 86, height: 86)

                VStack(spacing: 0) {
                    Text("76")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.primary)
                    Text("vandaag")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Text("Herstel")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(.label).opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

private struct TRIMPPreviewCard: View {
    let accent: Color

    /// Fourteen placeholder data points for the preview bars (normalized 0…1).
    private let bars: [CGFloat] = [0.35, 0.48, 0.30, 0.62, 0.55, 0.70, 0.40,
                                   0.58, 0.72, 0.45, 0.65, 0.80, 0.55, 0.68]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRIMP")
                .font(.caption2)
                .fontWeight(.semibold)
                .kerning(1.0)
                .foregroundColor(.secondary)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(bars.indices, id: \.self) { index in
                    Capsule()
                        .fill(accent.opacity(0.55 + (bars[index] * 0.45)))
                        .frame(width: 6, height: 50 * bars[index])
                }
            }
            .frame(height: 50, alignment: .bottom)
            .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("112")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                Text("/ dag")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Belasting")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color(.label).opacity(0.07), radius: 10, x: 0, y: 3)
    }
}
