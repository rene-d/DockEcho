import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: DockController!
    private var statusItem: NSStatusItem!
    private var primaryItem: NSMenuItem!
    private var displayItem: NSMenuItem!
    private var accessItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = Logo.image(size: 512)

        controller = DockController()
        controller.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "dock.rectangle",
                                           accessibilityDescription: "DockEcho")

        let menu = NSMenu()
        menu.addItem(withTitle: "About DockEcho…", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh Dock", action: #selector(refresh), keyEquivalent: "r").target = self
        primaryItem = menu.addItem(withTitle: "Also show on main display",
                                   action: #selector(togglePrimary), keyEquivalent: "")
        primaryItem.target = self
        primaryItem.state = controller.includePrimaryScreen ? .on : .off
        displayItem = menu.addItem(withTitle: "Open Apps on DockEcho's Display",
                                   action: #selector(toggleDisplay), keyEquivalent: "")
        displayItem.target = self
        displayItem.toolTip = "When an app has no window on the display you click, move its window there (requires the Accessibility permission)."
        displayItem.state = WindowMover.isEnabled ? .on : .off
        accessItem = menu.addItem(withTitle: "⚠️ Grant Accessibility Access…",
                                  action: #selector(grantAccess), keyEquivalent: "")
        accessItem.target = self
        accessItem.indentationLevel = 1
        accessItem.isHidden = true
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DockEcho", action: #selector(quit), keyEquivalent: "q").target = self
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func showAbout() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let credits = NSAttributedString(
            string: "Imagined by Daniel Glazman, created by Anthropic Claude",
            attributes: [.font: NSFont.systemFont(ofSize: 12),
                         .foregroundColor: NSColor.secondaryLabelColor,
                         .paragraphStyle: style])

        // The app is an accessory (no Dock icon): bring it forward so the panel is visible.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "DockEcho",
            .applicationIcon: Logo.image(size: 256),
            .applicationVersion: "1.0",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Free and open source"
        ])
    }

    @objc private func refresh() { controller.rebuildWindows() }

    @objc private func togglePrimary() {
        controller.includePrimaryScreen.toggle()
        primaryItem.state = controller.includePrimaryScreen ? .on : .off
    }

    @objc private func toggleDisplay() {
        WindowMover.isEnabled.toggle()
        displayItem.state = WindowMover.isEnabled ? .on : .off
    }

    /// The permission can be revoked, or invalidated by a re-signature, at any time.
    func menuWillOpen(_ menu: NSMenu) {
        displayItem.state = WindowMover.isEnabled ? .on : .off
        accessItem.isHidden = !WindowMover.needsPermission
    }

    @objc private func grantAccess() { WindowMover.openAccessibilitySettings() }

    @objc private func quit() { NSApp.terminate(nil) }
}
