import SwiftUI

/// The instant hover summary shown when the cursor enters the menu-bar icon.
/// Two compact lines (5-hour / 7-day) mirroring the popover's numbers, display
/// mode, and reset wording so it reads consistently with the rest of the app.
/// Deliberately tiny — reset text only, no gauges — since it's a glance aid.
struct HoverSummaryView: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var prefs: Preferences

    private var snap: UsageSnapshot { model.snapshot }
    private var modeLabel: String { prefs.showRemaining ? "남은 양" : "사용량" }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            row(window: "5시간", used: snap.fiveHourPercent, reset: snap.fiveHourResetText)
            row(window: "7일", used: snap.weeklyAllPercent, reset: snap.weeklyResetText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .fixedSize()
    }

    /// Display number follows the consumed/remaining mode via `Meter`, the
    /// single source of truth shared with the gauges/popover; color-free text
    /// keeps this surface minimal.
    private func row(window: String, used: Int, reset: String) -> some View {
        let display = Meter(usedPercent: used, showRemaining: prefs.showRemaining).displayPercent
        return HStack(spacing: 6) {
            Text("\(window) \(modeLabel)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(display)%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
            if !reset.isEmpty {
                Text("· \(reset)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
