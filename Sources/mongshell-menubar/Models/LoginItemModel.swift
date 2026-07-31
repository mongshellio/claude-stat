import SwiftUI

/// Owns the settings-window view of the launch-at-login state.
///
/// Deliberately **not** mirrored into `Preferences`: the system's Login Items
/// list is the SSOT (the user can flip it in System Settings at any time), so
/// `isEnabled` is only a cache of `LoginItemService.isEnabled`, refreshed when
/// the settings window opens. Not a singleton — only the settings window shows
/// this state, so `AppDelegate` owns the instance and injects it.
@MainActor
final class LoginItemModel: ObservableObject {
    @Published private(set) var isEnabled: Bool
    /// Last failure (or required follow-up in System Settings), surfaced under
    /// the toggle. nil when healthy.
    @Published private(set) var lastError: String?

    /// register() can report success while the user keeps the item switched
    /// off in System Settings — the toggle would silently snap back with no
    /// clue. Say what actually gates it.
    private static let approvalGuidance =
        "시스템 설정 > 일반 > 로그인 항목에서 이 앱을 허용해야 켜집니다."

    init() {
        isEnabled = LoginItemService.isEnabled
        lastError = Self.guidance(isEnabled: isEnabled)
    }

    /// Re-reads the system state. Called when the settings window (re)opens so
    /// a change made directly in System Settings is reflected — both the
    /// toggle and the guidance, which would otherwise go stale in either
    /// direction (allowed after the fact / switched off in a past session).
    func refresh() {
        isEnabled = LoginItemService.isEnabled
        lastError = Self.guidance(isEnabled: isEnabled)
    }

    /// Registers/unregisters, then re-reads the **system** state — on failure
    /// the toggle snaps back to the truth instead of showing the wish.
    func setEnabled(_ enabled: Bool) {
        var failure: String?
        do {
            try LoginItemService.setEnabled(enabled)
        } catch {
            failure = error.localizedDescription
        }
        isEnabled = LoginItemService.isEnabled

        // The guidance wins over a raw failure message: some macOS versions
        // make register() throw for an already-registered item, and then the
        // real blocker is the System Settings switch — only the guidance
        // tells the user what to do about it.
        lastError = Self.guidance(isEnabled: isEnabled) ?? failure
    }

    /// The System Settings follow-up guidance when it applies, nil otherwise.
    /// Shared by `init`/`refresh`/`setEnabled` so the guidance can never go
    /// stale relative to `isEnabled`.
    private static func guidance(isEnabled: Bool) -> String? {
        (!isEnabled && LoginItemService.requiresApproval) ? approvalGuidance : nil
    }
}
