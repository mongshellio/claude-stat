import Foundation

/// All I/O against Claude Code's user-scope settings file
/// (`~/.claude/settings.json`) lives here, isolated from the model the same way
/// `OpenClawService` isolates the gateway shell-outs.
///
/// That file — not UserDefaults — is the single source of truth for these
/// values. Claude Code watches it and hot-reloads, so a save here lands in an
/// already-running session for every key except `model`.
///
/// The file is **shared with the CLI**, which writes it too (`/effort`, `/fast`,
/// permission grants). So every save re-reads immediately before writing and
/// replaces only the keys we own; everything else survives byte-for-byte.
enum ClaudeSettingsStore {
    /// `~/.claude/settings.json`, overridable via `MONGSHELL_CLAUDE_SETTINGS`
    /// so development and QA never touch the real file.
    /// Symlinks are resolved because an atomic write replaces whatever sits at
    /// the path — dotfile setups that symlink this file into a repo would end
    /// up with the link swapped for a plain file.
    static var fileURL: URL {
        if let override = ProcessInfo.processInfo.environment["MONGSHELL_CLAUDE_SETTINGS"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
                .resolvingSymlinksInPath()
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
            .resolvingSymlinksInPath()
    }

    /// Claude Code is "installed" iff its config directory exists. We key off the
    /// directory, not the file: a fresh install has `~/.claude` but may not have
    /// written `settings.json` yet, and we're happy to create it.
    static var isInstalled: Bool {
        var isDir: ObjCBool = false
        let dir = fileURL.deletingLastPathComponent()
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    enum StoreError: LocalizedError {
        case notInstalled
        case unreadable
        case malformed

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Claude Code 설정 폴더(~/.claude)를 찾을 수 없습니다."
            case .unreadable:   return "settings.json 을 열 수 없습니다 (권한 또는 디스크 오류)."
            case .malformed:    return "settings.json 을 읽을 수 없습니다 (JSON 형식 오류)."
            }
        }
    }

    // MARK: Read

    /// The whole file as a dictionary.
    ///
    /// Only a genuinely absent file is an empty dictionary. Every other
    /// failure — unreadable, truncated, unparseable — throws, because callers
    /// use this result as the base for the next write: handing back `[:]` for a
    /// file we simply failed to read would turn the next save into a wipe of
    /// every setting we can't see.
    static func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw StoreError.unreadable
        }
        // A file that exists but holds nothing is the debris of an interrupted
        // write, not a fresh install.
        guard !data.isEmpty else { throw StoreError.malformed }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            throw StoreError.malformed
        }
        return dict
    }

    // MARK: Write

    /// Read-modify-write. The read happens here, immediately before the write,
    /// so a key the CLI changed a moment ago is carried into the new file
    /// instead of being clobbered by a stale in-memory copy.
    ///
    /// Returns the dictionary as written, so callers can refresh their UI from
    /// what actually landed on disk rather than from what they intended.
    @discardableResult
    static func mutate(_ transform: (inout [String: Any]) -> Void) throws -> [String: Any] {
        guard isInstalled else { throw StoreError.notInstalled }

        var dict = try load()
        transform(&dict)

        // Keep one copy of the previous contents. Best-effort: a missing file or
        // an unwritable backup must not block the save itself.
        let backup = fileURL.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }

        // `.sortedKeys` costs us the author's key order once, but makes our
        // writes deterministic and diffable. `.withoutEscapingSlashes` keeps
        // path-shaped permission rules readable.
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        // `.atomic` writes a temp file and renames — a crash mid-write can never
        // leave a truncated settings.json behind.
        try data.write(to: fileURL, options: .atomic)
        return dict
    }

    // MARK: Nested helpers

    /// Sets `dict[key] = value`, or clears the key when `value` is nil. Absent
    /// and "explicitly set to the default" are different things in a layered
    /// settings file, so we never write a placeholder.
    ///
    /// `understood` decides whether an existing value may be cleared, and must
    /// match the cast the reader uses. A key holding an unexpected type reads
    /// back as "absent" too, and deleting on that basis would throw away a
    /// setting the user never touched here — so anything we can't read is left
    /// exactly as it is.
    static func set(_ dict: inout [String: Any],
                    _ key: String,
                    _ value: Any?,
                    understood: (Any) -> Bool) {
        if let value {
            dict[key] = value
            return
        }
        guard let existing = dict[key] else { return }
        guard understood(existing) else { return }
        dict.removeValue(forKey: key)
    }

    /// Same, one level down. An object left empty by the removal is dropped too,
    /// so toggling a nested key back to default doesn't leave `{}` behind. A
    /// parent that isn't an object is left untouched for the same reason as
    /// above.
    static func setNested(_ dict: inout [String: Any],
                          _ parent: String,
                          _ key: String,
                          _ value: Any?,
                          understood: (Any) -> Bool) {
        if dict[parent] != nil && dict[parent] as? [String: Any] == nil { return }

        var child = dict[parent] as? [String: Any] ?? [:]
        set(&child, key, value, understood: understood)
        if child.isEmpty {
            dict.removeValue(forKey: parent)
        } else {
            dict[parent] = child
        }
    }
}

/// Watches the settings file and fires `onChange` when it moves underneath us.
///
/// Claude Code (like us) saves atomically, which replaces the inode rather than
/// writing through the existing one — so a plain `.write` watch goes deaf after
/// the first external save. We therefore watch for `.delete`/`.rename` as well
/// and re-arm on a fresh descriptor.
/// `source`, `pendingArm` and `stopped` are reached from the watch queue, from
/// the caller's thread, and from `deinit`, so a lock guards them rather than
/// pretending one thread owns them. `onChange` is `@Sendable` because it is
/// stored here and always invoked on `queue`, never on the caller's thread.
/// Together those are what the `@unchecked Sendable` claim rests on.
final class ClaudeSettingsWatcher: @unchecked Sendable {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var pendingArm: DispatchWorkItem?
    private var stopped = false
    private let queue = DispatchQueue(label: "com.mongshell.menubar.claude-settings-watch")

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        lock.lock()
        stopped = false
        lock.unlock()
        arm()
    }

    /// Tears the watch down for good. Without the `stopped` flag a scheduled
    /// re-arm would quietly resurrect it seconds later.
    func stop() {
        lock.lock()
        stopped = true
        let old = source
        let pending = pendingArm
        source = nil
        pendingArm = nil
        lock.unlock()
        pending?.cancel()
        old?.cancel()
    }

    /// Installs `new` and cancels whatever it replaced. Cancelling outside the
    /// lock keeps the cancel handler (which closes the fd) off a held lock.
    private func swap(_ new: DispatchSourceFileSystemObject?) {
        lock.lock()
        let old = source
        source = new
        lock.unlock()
        old?.cancel()
    }

    /// Arms after `delay`, replacing any arm already queued. `notifying` fires
    /// one extra read after re-arming: writes that land while no descriptor is
    /// open produce no event of their own, so without it the gap is silent.
    private func scheduleArm(after delay: TimeInterval, notifying: Bool) {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.arm()
            if notifying { self.onChange() }
        }
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        pendingArm?.cancel()
        pendingArm = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func arm() {
        lock.lock()
        let isStopped = stopped
        lock.unlock()
        guard !isStopped else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // No file yet (fresh install). Retry rather than giving up, so the
            // first CLI write still reaches us.
            scheduleArm(after: 5, notifying: false)
            return
        }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )
        // `src` is captured weakly: a strong capture would make the source
        // retain its own handler, so it could only ever be freed by cancel.
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let flags = src.data
            self.onChange()
            // The file we held is gone — pick up its replacement. A short delay
            // lets the writer finish its rename before we reopen.
            if flags.contains(.delete) || flags.contains(.rename) {
                self.scheduleArm(after: 0.2, notifying: true)
            }
        }
        src.setCancelHandler { close(fd) }
        swap(src)
        src.resume()
    }
}
