import Foundation
import SwiftUI
import AppKit
import UserNotifications

/// Owns the openclaw gateway health + drives its own polling loop, mirroring
/// `UsageModel` but shelling out via `Process` instead of hitting HTTP.
///
/// Shared singleton so the AppKit status item and SwiftUI views agree. On a
/// mac without openclaw this parks in `.notInstalled` and never polls, so the
/// app is byte-for-byte the same as before.
@MainActor
final class OpenClawModel: ObservableObject {
    static let shared = OpenClawModel()

    @Published private(set) var health: OpenClawHealth = .unknown
    /// Gateway PID, for display in the popover.
    @Published private(set) var pid: Int?

    private var pollTask: Task<Void, Never>?

    // Auto-heal bookkeeping.
    private var consecutiveFailures = 0
    private var lastHealAt: Date?
    private let healCooldown: TimeInterval = 600

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard OpenClawService.isInstalled else {
            health = .notInstalled
            return
        }
        if Preferences.shared.openClawAutoHeal { requestNotificationAuth() }
        pollTask?.cancel()
        pollTask = Task { [weak self] in await self?.pollLoop() }
    }

    func refreshNow() {
        Task { await refreshOnce() }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refreshOnce()
            let secs = max(15, Preferences.shared.openClawPollSeconds)
            try? await Task.sleep(for: .seconds(secs))
        }
    }

    // MARK: Refresh

    /// Probe + PID lookup run off-main (they block 1–3s); only the results land
    /// back on the main actor.
    private func refreshOnce() async {
        let (newHealth, newPID) = await Task.detached(priority: .utility) {
            (OpenClawService.probe(), OpenClawService.gatewayPID())
        }.value

        health = newHealth
        pid = newPID
        await maybeAutoHeal(for: newHealth)
    }

    // MARK: Auto-heal

    /// Hard-restart only when: enabled, the state is a real failure, it's the
    /// 2nd consecutive failure, and we're past the cooldown. Notifies once.
    private func maybeAutoHeal(for health: OpenClawHealth) async {
        guard Preferences.shared.openClawAutoHeal else {
            consecutiveFailures = 0
            return
        }

        let isFailure: Bool
        switch health {
        case .down, .degraded: isFailure = true
        default: isFailure = false
        }
        guard isFailure else {
            consecutiveFailures = 0
            return
        }

        consecutiveFailures += 1
        guard consecutiveFailures >= 2 else { return }
        if let last = lastHealAt, Date().timeIntervalSince(last) < healCooldown { return }

        lastHealAt = Date()
        consecutiveFailures = 0

        let ok = await Task.detached(priority: .utility) {
            OpenClawService.hardRestart()
        }.value
        notifyHeal(success: ok, health: health)

        // Give launchd a moment, then reflect recovery.
        try? await Task.sleep(for: .seconds(3))
        await refreshOnce()
    }

    // MARK: Manual actions

    /// User-initiated hard restart from the popover.
    func hardRestart() {
        Task {
            _ = await Task.detached(priority: .utility) {
                OpenClawService.hardRestart()
            }.value
            try? await Task.sleep(for: .seconds(2))
            await refreshOnce()
        }
    }

    func openDashboard() {
        guard let url = URL(string: "http://127.0.0.1:18789/") else { return }
        NSWorkspace.shared.open(url)
    }

    func openLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/openclaw/gateway.log")
        NSWorkspace.shared.open(url)
    }

    // MARK: Notifications

    /// UserNotifications requires a real app bundle; guard so an unbundled
    /// `swift run` dev launch doesn't crash. (Same pattern as `UsageModel`.)
    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationAuth() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyHeal(success: Bool, health: OpenClawHealth) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = success ? "openclaw 자동 재시작됨" : "openclaw 재시작 실패"
        if success {
            switch health {
            case .degraded(let d):
                content.body = "채널 이상(\(d)) 감지 — 하드 재시작했습니다."
            case .down:
                content.body = "게이트웨이 다운 감지 — 하드 재시작했습니다."
            default:
                content.body = "먹통 감지 — 하드 재시작했습니다."
            }
        } else {
            content.body = "launchctl 하드 재시작에 실패했습니다."
        }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "openclaw-heal", content: content, trigger: nil)
        )
    }
}
