import SwiftUI

/// The status-bar content: Claude mark + `5h NN% · 7d NN%`. Hosted inside the
/// NSStatusItem button via NSHostingView. The mark pulses at ≥90% (per the
/// design's alert behavior).
struct MenuBarIconView: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var prefs: Preferences

    @State private var pulsing = false

    private var fiveHourUsed: Int { model.snapshot.fiveHourPercent }
    private var weeklyUsed: Int { model.snapshot.weeklyAllPercent }

    /// Pulse always keys off risk (consumed) of the riskier window,
    /// regardless of display mode.
    private var shouldPulse: Bool {
        prefs.pulseWhenCritical && max(fiveHourUsed, weeklyUsed) >= 90
    }

    var body: some View {
        MenuBarContent(fiveHourUsed: fiveHourUsed, weeklyUsed: weeklyUsed,
                       showRemaining: prefs.showRemaining,
                       colorCoding: prefs.colorCoding,
                       showPercent: prefs.showPercent,
                       fiveHourReset: TimeText.clockShort(model.snapshot.fiveHourResetAt),
                       weeklyReset: TimeText.weekdayClockShort(model.snapshot.weeklyResetAt),
                       pulsing: pulsing)
        .animation(shouldPulse
                   ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
                   : .default,
                   value: pulsing)
        .onAppear { pulsing = shouldPulse }
        .onChange(of: shouldPulse) { _, now in pulsing = now }
    }
}

/// The bar's visual content, parameterized so the live menu bar and the
/// offscreen snapshot renderer share one layout.
struct MenuBarContent: View {
    let fiveHourUsed: Int
    let weeklyUsed: Int
    let showRemaining: Bool
    let colorCoding: Bool
    let showPercent: Bool
    var fiveHourReset: String? = nil
    var weeklyReset: String? = nil
    var pulsing: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            ClaudeMarkView()
                .frame(width: 16, height: 16)
                .scaleEffect(pulsing ? 1.14 : 1.0)

            if showPercent {
                metric("5h", fiveHourUsed, reset: fiveHourReset)
                Text("·")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                metric("7d", weeklyUsed, reset: weeklyReset)
            }
        }
        .padding(.horizontal, 2)
        .fixedSize()
    }

    /// One `label NN% (reset)` unit. The number shows consumed or remaining per
    /// the display mode; its color always tracks risk (consumed). The reset
    /// clock is dimmed so the percent stays the loudest element.
    private func metric(_ label: String, _ used: Int, reset: String?) -> some View {
        HStack(spacing: 2.5) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(showRemaining ? 100 - used : used)%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(colorCoding
                                 ? Palette.statusColor(for: used, colorCoding: true)
                                 : Color.primary)
            if let reset {
                Text("(\(reset))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
