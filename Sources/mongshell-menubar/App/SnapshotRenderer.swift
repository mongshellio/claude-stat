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

        return true
    }

    private static func write<V: View>(_ view: V, to dir: URL, _ name: String, scale: CGFloat) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
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
                               fiveHourReset: "14:40", weeklyReset: "일 21:59")
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(scheme == .dark ? Color(hex: 0x2C2C30) : Color(hex: 0xE8E6E1))
    }
}

/// The live popover with sample data.
private struct PopoverPreview: View {
    var body: some View {
        PopoverView(
            model: UsageModel.shared, prefs: Preferences.shared,
            onOpenSettings: {}, onQuit: {}
        )
        .padding(24)
        .background(Color(hex: 0xE8E6E1))
    }
}
