import SwiftUI
import AppKit

/// Offscreen PNG rendering for visual QA (no screen-recording permission
/// needed). Triggered by the MONGSHELL_SNAPSHOT=<dir> env var; renders reference
/// images then exits.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested() -> Bool {
        guard let dir = ProcessInfo.processInfo.environment["MONGSHELL_SNAPSHOT"] else { return false }
        let base = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        write(MenuBarStrip(scheme: .dark).frame(width: 700, height: 44)
                .environment(\.colorScheme, .dark),
              to: base, "menubar_strip_dark", scale: 3)
        write(MenuBarStrip(scheme: .light).frame(width: 700, height: 44)
                .environment(\.colorScheme, .light),
              to: base, "menubar_strip_light", scale: 3)
        write(PopoverPreview(), to: base, "popover", scale: 2)

        // The Claude Code section renders whatever settings file it is pointed
        // at, so default to a fixture: reference images must never carry the
        // operator's own model choice or permission mode. An explicit
        // MONGSHELL_CLAUDE_SETTINGS still wins.
        if ProcessInfo.processInfo.environment["MONGSHELL_CLAUDE_SETTINGS"] == nil {
            let fixture = base.appendingPathComponent("claude-settings-fixture.json")
            let json = #"{"model":"opus","effortLevel":"high","permissions":{"defaultMode":"auto"}}"#
            try? json.write(to: fixture, atomically: true, encoding: .utf8)
            setenv("MONGSHELL_CLAUDE_SETTINGS", fixture.path, 1)
        }
        ClaudeSettingsModel.shared.start()
        writeWindowed(SettingsPreview(), size: NSSize(width: 380, height: 700),
                      to: base, "settings")
        writeWindowed(ClaudeSectionPreview(), size: NSSize(width: 380, height: 560),
                      to: base, "settings_claude")

        return true
    }

    /// `Form` is AppKit-backed and comes out blank through `ImageRenderer`, so
    /// form-based views are hosted in an off-screen window and captured with
    /// `cacheDisplay`. Still headless — the window is parked far off any screen
    /// and never becomes key.
    private static func writeWindowed<V: View>(_ view: V, size: NSSize,
                                               to dir: URL, _ name: String) {
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.contentViewController = NSHostingController(rootView: view)
        win.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        win.orderFrontRegardless()
        defer { win.close() }

        guard let content = win.contentView else {
            report("\(name): no content view")
            return
        }
        content.layoutSubtreeIfNeeded()
        // SwiftUI populates the form on the next runloop passes; capturing
        // immediately yields an empty view.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            report("\(name): capture failed")
            return
        }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            report("\(name): PNG encode failed")
            return
        }
        do {
            try png.write(to: dir.appendingPathComponent("\(name).png"))
        } catch {
            // A silently missing reference image reads as "nothing changed".
            report("\(name): \(error)")
        }
    }

    private static func write<V: View>(_ view: V, to dir: URL, _ name: String, scale: CGFloat) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            report("\(name): render failed")
            return
        }
        do {
            try png.write(to: dir.appendingPathComponent("\(name).png"))
        } catch {
            report("\(name): \(error)")
        }
    }

    /// A silently missing reference image reads as "nothing changed", so every
    /// failure path says so on stderr.
    private static func report(_ message: String) {
        FileHandle.standardError.write(Data("snapshot \(message)\n".utf8))
    }
}

// MARK: - Preview views

/// Menu-bar mock: Claude mark + `5h · 7d` text at three usage-level pairs.
private struct MenuBarStrip: View {
    let scheme: ColorScheme
    var body: some View {
        HStack(spacing: 26) {
            ForEach([(12, 34), (62, 45), (95, 91)], id: \.0) { five, weekly in
                MenuBarContent(fiveHourUsed: five, weeklyUsed: weekly,
                               showRemaining: false, colorCoding: true,
                               showPercent: true,
                               fiveHourReset: "19:00")
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(scheme == .dark ? Color(hex: 0x2C2C30) : Color(hex: 0xE8E6E1))
    }
}

/// The settings window as shipped. The login-item model reads live system
/// state, but the snapshot binary is unbundled and never registered, so the
/// toggle renders deterministically off.
private struct SettingsPreview: View {
    var body: some View {
        SettingsView(model: .shared, prefs: .shared,
                     openClaw: .shared, claude: .shared,
                     loginItem: LoginItemModel())
    }
}

/// The Claude Code section alone — the window scrolls, so this is the only way
/// to see every row of it in one image.
private struct ClaudeSectionPreview: View {
    var body: some View {
        Form {
            Section("Claude Code") {
                ClaudeSettingsSection(claude: .shared)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 560)
    }
}

/// The live popover with sample data.
private struct PopoverPreview: View {
    var body: some View {
        PopoverView(
            model: UsageModel.shared, prefs: Preferences.shared, openClaw: OpenClawModel.shared,
            onOpenSettings: {}, onQuit: {}
        )
        .padding(24)
        .background(Color(hex: 0xE8E6E1))
    }
}
