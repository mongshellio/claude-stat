import SwiftUI
import AppKit
import Combine

/// An NSHostingView that lets mouse events fall through to the status-item
/// button underneath, so the button's click action still fires while the
/// SwiftUI icon keeps animating (e.g. the ≥90% pulse).
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var hostingView: PassthroughHostingView<MenuBarIconView>!
    private var cancellables = Set<AnyCancellable>()

    // Second (optional) status item for openclaw. Nil unless the user opted in
    // AND openclaw is installed; created/torn down live as that changes.
    private var openClawStatusItem: NSStatusItem?
    private var openClawPopover: NSPopover?
    private var openClawHostingView: PassthroughHostingView<OpenClawStatusView>?

    private let model = UsageModel.shared
    private let prefs = Preferences.shared
    private let openClaw = OpenClawModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // QA hook: render reference PNGs offscreen, then exit.
        if SnapshotRenderer.runIfRequested() {
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }

        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = MenuBarIconView(model: model, prefs: prefs)
        hostingView = PassthroughHostingView(rootView: icon)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        if let button = statusItem.button {
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                hostingView.centerXAnchor.constraint(equalTo: button.centerXAnchor)
            ])
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover = NSPopover()
        popover.behavior = .transient
        let content = PopoverView(
            model: model, prefs: prefs,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        let hc = NSHostingController(rootView: content)
        hc.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hc

        // Keep the status-item width in sync with icon content.
        model.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in self?.resizeStatusItem() }
            .store(in: &cancellables)
        prefs.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.resizeStatusItem()
                // menuBarTarget may have flipped — add/remove the openclaw item
                // live, no app restart.
                self?.updateOpenClawItem()
            }
        }.store(in: &cancellables)

        resizeStatusItem()
        model.start()

        // No-op internally if openclaw isn't installed.
        openClaw.start()
        updateOpenClawItem()
    }

    private func resizeStatusItem() {
        hostingView.layoutSubtreeIfNeeded()
        let w = max(24, hostingView.fittingSize.width)
        statusItem.length = w
    }

    // MARK: openclaw status item (conditional)

    /// Adds or removes the openclaw item to match the current setting. Only
    /// present when the user picked `Claude + openclaw` AND openclaw is
    /// installed — otherwise the app looks exactly like the Claude-only build.
    private func updateOpenClawItem() {
        let shouldShow = prefs.menuBarTarget == .claudeAndOpenClaw && OpenClawService.isInstalled
        if shouldShow {
            if openClawStatusItem == nil { installOpenClawItem() }
        } else {
            removeOpenClawItem()
        }
    }

    private func installOpenClawItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The SwiftUI dot observes `openClaw.health`, so its color updates live.
        let host = PassthroughHostingView(rootView: OpenClawStatusView(model: openClaw))
        host.translatesAutoresizingMaskIntoConstraints = false
        if let button = item.button {
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                host.centerXAnchor.constraint(equalTo: button.centerXAnchor)
            ])
            button.target = self
            button.action = #selector(toggleOpenClawPopover)
        }
        item.length = 22

        let pop = NSPopover()
        pop.behavior = .transient
        let hc = NSHostingController(rootView: OpenClawPopoverView(model: openClaw))
        hc.sizingOptions = [.preferredContentSize]
        pop.contentViewController = hc

        openClawStatusItem = item
        openClawHostingView = host
        openClawPopover = pop
    }

    private func removeOpenClawItem() {
        openClawPopover?.performClose(nil)
        if let item = openClawStatusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        openClawStatusItem = nil
        openClawHostingView = nil
        openClawPopover = nil
    }

    @objc private func toggleOpenClawPopover() {
        guard let button = openClawStatusItem?.button, let pop = openClawPopover else { return }
        if pop.isShown {
            pop.performClose(nil)
        } else {
            openClaw.refreshNow() // freshen on open
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            pop.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(model: model, prefs: prefs, openClaw: openClaw)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = "mongshell-menubar 설정"
        win.contentViewController = NSHostingController(rootView: view)
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
