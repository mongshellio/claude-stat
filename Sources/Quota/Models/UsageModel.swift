import Foundation
import SwiftUI
import UserNotifications

/// Owns the usage snapshot + connection state and drives polling.
/// Shared singleton so the AppKit status item and SwiftUI views agree.
@MainActor
final class UsageModel: ObservableObject {
    static let shared = UsageModel()

    @Published private(set) var snapshot: UsageSnapshot = .sample
    @Published private(set) var loadState: LoadState = .signedOut

    private let api = UsageAPIClient()
    private let auth = AuthService()
    private var pollTask: Task<Void, Never>?
    private var backoff: Int = 0
    private var lastNotifiedLevel = 0

    // MARK: Lifecycle

    func start() {
        if Preferences.shared.notifyThresholds { requestNotificationAuth() }
        pollTask?.cancel()
        pollTask = Task { [weak self] in await self?.pollLoop() }
    }

    func refreshNow() {
        Task { await refreshOnce() }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refreshOnce()
            let base = max(Config.minPollInterval, Preferences.shared.pollIntervalSeconds)
            let wait = backoff > 0 ? min(base * (1 << backoff), 3600) : base
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    // MARK: Token resolution

    private func currentToken() -> (OAuthToken, DataSource)? {
        if let own = CredentialStore.loadOwnToken() { return (own, .oauthLogin) }
        if let cli = CredentialStore.loadClaudeCodeToken() { return (cli, .claudeCodeCLI) }
        return nil
    }

    // MARK: Refresh

    private func refreshOnce() async {
        guard let (initialToken, source) = currentToken() else {
            loadState = .signedOut
            snapshot = .sample
            return
        }
        var token = initialToken
        if case .signedOut = loadState { loadState = .loading }

        // Refresh our own expired token up front.
        if source == .oauthLogin, token.isExpired,
           let refreshed = try? await auth.refresh(token) {
            CredentialStore.saveOwnToken(refreshed)
            token = refreshed
        }

        do {
            let snap = try await api.fetch(token: token)
            snapshot = snap
            loadState = .loaded(source)
            backoff = 0
            maybeNotify(percent: snap.fiveHourPercent)
        } catch APIError.unauthorized {
            // Own token: try one refresh. CLI token: re-read (Claude Code may have rotated it).
            if source == .oauthLogin, let refreshed = try? await auth.refresh(token) {
                CredentialStore.saveOwnToken(refreshed)
                if let snap = try? await api.fetch(token: refreshed) {
                    snapshot = snap; loadState = .loaded(source); backoff = 0; return
                }
            }
            loadState = .signedOut
        } catch APIError.rateLimited(let retry) {
            backoff = min(backoff + 1, 4)
            loadState = .rateLimited(retryAfter: retry)
        } catch {
            loadState = .error("사용량을 불러오지 못했습니다")
        }
    }

    // MARK: Sign in / out

    func signIn() async {
        do {
            let token = try await auth.signIn()
            CredentialStore.saveOwnToken(token)
            await refreshOnce()
        } catch {
            loadState = .error((error as? LocalizedError)?.errorDescription ?? "로그인 실패")
        }
    }

    func signOut() {
        CredentialStore.clearOwnToken()
        loadState = .signedOut
        snapshot = .sample
    }

    // MARK: Notifications

    /// UserNotifications requires a real app bundle; guard so an unbundled
    /// `swift run` dev launch doesn't crash.
    private var notificationsAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationAuth() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func maybeNotify(percent: Int) {
        guard Preferences.shared.notifyThresholds, notificationsAvailable else { return }
        let thresholds = [90, 75, 50, 25]
        let level = thresholds.first(where: { percent >= $0 }) ?? 0
        guard level > lastNotifiedLevel else {
            if percent < 25 { lastNotifiedLevel = 0 } // reset after window resets
            return
        }
        lastNotifiedLevel = level
        let content = UNMutableNotificationContent()
        content.title = "Claude 사용량 \(level)% 도달"
        content.body = level >= 90 ? "곧 한도에 도달합니다." : "사용량이 \(percent)%입니다."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "quota-\(level)", content: content, trigger: nil)
        )
    }
}
