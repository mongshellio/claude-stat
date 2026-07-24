import SwiftUI
import Combine

/// User settings, persisted in UserDefaults. Shared singleton so both the
/// AppKit status-item host and SwiftUI views observe the same instance.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @AppStorage("colorCoding") var colorCoding: Bool = true
    @AppStorage("showPercent") var showPercent: Bool = true
    /// false = show consumed amount (기본), true = show remaining amount.
    /// Only flips the displayed number + gauge fill; color still tracks risk.
    @AppStorage("showRemaining") var showRemaining: Bool = false
    /// Polling interval in seconds. 180 (the endpoint's safe floor) is the
    /// default — usage %s change slowly, so this is the freshest safe cadence.
    /// The option exists mainly as a 429 escape valve / battery saver.
    @AppStorage("pollIntervalSeconds") var pollIntervalSeconds: Int = 180
    @AppStorage("notifyThresholds") var notifyThresholds: Bool = true
    @AppStorage("pulseWhenCritical") var pulseWhenCritical: Bool = true

    private init() {}
}
