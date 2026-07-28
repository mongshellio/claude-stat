import SwiftUI
import Combine

/// The subset of `~/.claude/settings.json` this app edits.
///
/// Empty string means "키 없음" — the setting is absent from the file and Claude
/// Code's own default applies. That's deliberately distinct from writing the
/// default value out explicitly.
struct ClaudeSettings: Equatable {
    var model: String = ""
    var effortLevel: String = ""
    var fallbackPrimary: String = ""
    var fallbackSecondary: String = ""
    /// Claude Code defaults this to true, so `true` is stored as key-absent and
    /// only the non-default `false` is written out.
    var autoCompact: Bool = true
    var permissionMode: String = ""
}

/// Owns the live view of Claude Code's settings file.
///
/// Deliberately **not** backed by `@AppStorage`: unlike `Preferences`, these
/// values belong to Claude Code and the CLI edits them too, so mirroring them
/// into UserDefaults would create a second, silently-diverging copy. The file
/// is the only authority; we read it, write it, and watch it.
@MainActor
final class ClaudeSettingsModel: ObservableObject {
    static let shared = ClaudeSettingsModel()

    @Published private(set) var settings = ClaudeSettings()
    @Published private(set) var isInstalled = false
    /// Last read/write failure, surfaced in the settings UI. nil when healthy.
    @Published private(set) var lastError: String?

    private var watcher: ClaudeSettingsWatcher?

    private init() {}

    // MARK: Lifecycle

    /// Loads the file and starts watching it. A no-op when Claude Code isn't
    /// installed, mirroring how `OpenClawModel` parks without openclaw.
    func start() {
        // Tear down any previous watch first, mirroring `OpenClawModel.start()`.
        watcher?.stop()
        watcher = nil

        isInstalled = ClaudeSettingsStore.isInstalled
        guard isInstalled else { return }

        reload()

        let w = ClaudeSettingsWatcher(url: ClaudeSettingsStore.fileURL) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        w.start()
        watcher = w
    }

    /// Re-reads the file into `settings`. Never writes — this is the path the
    /// watcher takes when the CLI (`/effort`, `/fast`, permission grants) edits
    /// the file behind us, so it must not bounce a save back.
    func reload() {
        do {
            settings = Self.parse(try ClaudeSettingsStore.load())
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Bindings

    /// Binding that saves on every change. Reads go through `settings`, which
    /// `reload()` owns, so an external edit wins the moment it lands.
    func binding<V>(_ keyPath: WritableKeyPath<ClaudeSettings, V>) -> Binding<V> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                var next = self.settings
                next[keyPath: keyPath] = newValue
                self.save(next)
            }
        )
    }

    // MARK: Persistence

    private func save(_ next: ClaudeSettings) {
        // Optimistic: reflect the click immediately, then reconcile with what
        // actually landed on disk.
        settings = next
        do {
            let written = try ClaudeSettingsStore.mutate { dict in
                Self.apply(next, to: &dict)
            }
            settings = Self.parse(written)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            reload() // roll the UI back to the truth on disk
        }
    }

    // MARK: JSON ↔ struct

    /// Pure, and deliberately `nonisolated` + internal: the JSON mapping is the
    /// part worth exercising directly, and it has no business needing the main
    /// actor to do it.
    nonisolated static func parse(_ dict: [String: Any]) -> ClaudeSettings {
        var s = ClaudeSettings()
        s.model = dict["model"] as? String ?? ""
        s.effortLevel = dict["effortLevel"] as? String ?? ""

        let fallback = dict["fallbackModel"] as? [String] ?? []
        s.fallbackPrimary = fallback.count > 0 ? fallback[0] : ""
        s.fallbackSecondary = fallback.count > 1 ? fallback[1] : ""

        s.autoCompact = dict["autoCompactEnabled"] as? Bool ?? true

        let permissions = dict["permissions"] as? [String: Any]
        s.permissionMode = permissions?["defaultMode"] as? String ?? ""
        return s
    }

    /// Each `understood` predicate mirrors the cast `parse` uses for that key,
    /// so a value we couldn't read is never mistaken for one the user cleared.
    nonisolated static func apply(_ s: ClaudeSettings, to dict: inout [String: Any]) {
        ClaudeSettingsStore.set(&dict, "model",
                                s.model.isEmpty ? nil : s.model) { $0 is String }
        ClaudeSettingsStore.set(&dict, "effortLevel",
                                s.effortLevel.isEmpty ? nil : s.effortLevel) { $0 is String }

        // Order carries meaning (1차 then 2차), so a blank 1차 promotes 2차
        // rather than leaving a hole. Duplicates would be dead entries.
        var chain = [s.fallbackPrimary, s.fallbackSecondary].filter { !$0.isEmpty }
        chain = chain.reduce(into: [String]()) { acc, m in if !acc.contains(m) { acc.append(m) } }
        ClaudeSettingsStore.set(&dict, "fallbackModel",
                                chain.isEmpty ? nil : chain) { $0 is [String] }

        // true is Claude Code's default — leave the key out rather than writing
        // a value that only restates it.
        ClaudeSettingsStore.set(&dict, "autoCompactEnabled",
                                s.autoCompact ? nil : false) { $0 is Bool }

        ClaudeSettingsStore.setNested(&dict, "permissions", "defaultMode",
                                      s.permissionMode.isEmpty ? nil : s.permissionMode) {
            $0 is String
        }
    }
}

// MARK: - Choices

/// A single Picker choice: the value written to JSON plus its Korean label.
struct ClaudeChoice: Identifiable, Hashable {
    let value: String
    let label: String
    var id: String { value }
}

enum ClaudeChoices {
    /// Model aliases rather than pinned IDs — aliases keep tracking the current
    /// generation instead of going stale on the next release.
    static let models: [ClaudeChoice] = [
        .init(value: "opus", label: "Opus (가장 강력)"),
        .init(value: "sonnet", label: "Sonnet (균형)"),
        .init(value: "haiku", label: "Haiku (가장 빠름)"),
        .init(value: "fable", label: "Fable"),
    ]

    static let efforts: [ClaudeChoice] = [
        .init(value: "low", label: "낮음 (low)"),
        .init(value: "medium", label: "보통 (medium)"),
        .init(value: "high", label: "높음 (high)"),
        .init(value: "xhigh", label: "매우 높음 (xhigh)"),
    ]

    /// `allow`(전부 허용) is intentionally absent: a mis-click in a GUI that
    /// silently grants every tool call is a worse trade than the convenience.
    /// Anyone who wants it can still set it in the file by hand.
    static let permissionModes: [ClaudeChoice] = [
        .init(value: "ask", label: "매번 확인 (ask)"),
        .init(value: "auto", label: "자동 분류 (auto)"),
        .init(value: "deny", label: "전부 차단 (deny)"),
    ]

    /// Prepends the "key absent" choice and, when the file holds a value we
    /// don't know (a pinned model ID, a mode we don't list), appends it so the
    /// Picker shows the truth instead of going blank — and so merely opening
    /// the window can't silently rewrite it.
    static func options(_ known: [ClaudeChoice],
                        current: String,
                        emptyLabel: String) -> [ClaudeChoice] {
        var all = [ClaudeChoice(value: "", label: emptyLabel)] + known
        if !current.isEmpty && !known.contains(where: { $0.value == current }) {
            all.append(ClaudeChoice(value: current, label: "\(current) (직접 설정한 값)"))
        }
        return all
    }
}
