import AppKit

final class DockWindow: NSPanel {
    private let root = DockRootView()
    private var items: [DockItem] = []
    private var settings = DockSettings()
    private var metrics = DockMetrics(settings: DockSettings())
    private var screenFrame = NSRect.zero
    private var shownFrame = NSRect.zero

    private var isRevealed = true
    private var edgeSince: Date?
    private var leaveSince: Date?

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = root
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func update(items newItems: [DockItem], settings newSettings: DockSettings, on screen: NSScreen) {
        items = newItems
        screenFrame = screen.frame

        let vertical = newSettings.orientation != .bottom
        let available = vertical ? screen.frame.height : screen.frame.width
        let fitted = DockMetrics.fitted(newSettings, items: newItems, available: available)

        let wasAutohide = settings.autohide
        settings = fitted
        metrics = DockMetrics(settings: fitted)
        root.configure(items: newItems, settings: fitted)

        let length = min(metrics.windowLength(newItems), available)
        let thickness = min(metrics.thickness, vertical ? screen.frame.width : screen.frame.height)
        let margin: CGFloat = 4

        switch fitted.orientation {
        case .bottom:
            shownFrame = NSRect(x: screen.frame.midX - length / 2, y: screen.frame.minY + margin,
                                width: length, height: thickness)
        case .left:
            shownFrame = NSRect(x: screen.frame.minX + margin, y: screen.frame.midY - length / 2,
                                width: thickness, height: length)
        case .right:
            shownFrame = NSRect(x: screen.frame.maxX - margin - thickness, y: screen.frame.midY - length / 2,
                                width: thickness, height: length)
        }
        setFrame(shownFrame, display: true)

        if fitted.autohide {
            if !wasAutohide { setRevealed(false, animated: false) }
        } else {
            setRevealed(true, animated: false)
        }
    }

    // MARK: Auto-hide

    private func zone(depth: CGFloat, extra: CGFloat) -> NSRect {
        let total = metrics.baseLayout(items).total + extra * 2
        switch metrics.orientation {
        case .bottom:
            return NSRect(x: shownFrame.midX - total / 2, y: screenFrame.minY, width: total, height: depth)
        case .left:
            return NSRect(x: screenFrame.minX, y: shownFrame.midY - total / 2, width: depth, height: total)
        case .right:
            return NSRect(x: screenFrame.maxX - depth, y: shownFrame.midY - total / 2, width: depth, height: total)
        }
    }

    private func setRevealed(_ revealed: Bool, animated: Bool) {
        isRevealed = revealed
        edgeSince = nil
        leaveSince = nil
        ignoresMouseEvents = !revealed
        if !revealed { root.icons.resetHover() }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = max(0.05, 0.25 * settings.autohideTimeModifier)
                self.animator().alphaValue = revealed ? 1 : 0
            }
        } else {
            alphaValue = revealed ? 1 : 0
        }
    }

    /// Called about 20 times per second while auto-hide is active.
    func autohideTick(mouse: NSPoint) {
        guard settings.autohide else { return }
        let now = Date()
        if isRevealed {
            let active = zone(depth: 4 + metrics.shelfThickness + metrics.overhang + 12, extra: metrics.base)
            if active.contains(mouse) {
                leaveSince = nil
            } else {
                if leaveSince == nil { leaveSince = now }
                if now.timeIntervalSince(leaveSince!) > 0.15 { setRevealed(false, animated: true) }
            }
        } else {
            let hot = zone(depth: 3, extra: metrics.base * 2)
            if hot.contains(mouse) {
                if edgeSince == nil { edgeSince = now }
                if now.timeIntervalSince(edgeSince!) >= settings.autohideDelay { setRevealed(true, animated: true) }
            } else {
                edgeSince = nil
            }
        }
    }
}

final class DockController {
    private static let includePrimaryKey = "includePrimaryScreen"

    private var windows: [DockWindow] = []
    private var items: [DockItem] = []
    private var settings = DockSettings()
    private var lastRaw: NSDictionary = [:]
    private var prefsTimer: Timer?
    private var autohideTimer: Timer?

    /// By default the primary display (the one with the menu bar, where the real Dock lives) is excluded.
    var includePrimaryScreen: Bool {
        get { UserDefaults.standard.bool(forKey: Self.includePrimaryKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.includePrimaryKey)
            rebuildWindows()
        }
    }

    private var targetScreens: [NSScreen] {
        let all = NSScreen.screens
        return includePrimaryScreen ? all : Array(all.dropFirst())
    }

    func start() {
        TrashState.refresh()
        lastRaw = DockSettings.rawSnapshot()
        rebuildWindows()

        // Apps launched / quit
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(self, selector: #selector(refreshItems), name: name, object: nil)
        }
        // Displays plugged / unplugged / reconfigured
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWindows),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        // Changes to the main Dock: preferences notification + periodic check
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(checkPreferences),
                                                            name: NSNotification.Name("com.apple.dock.prefchanged"),
                                                            object: nil)
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.checkPreferences() }
        RunLoop.main.add(t, forMode: .common)
        prefsTimer = t
    }

    /// Re-reads the Dock preferences; only recomputes if something actually changed.
    @objc func checkPreferences() {
        if TrashState.refresh() { refreshItems() }   // empty <-> full Trash icon
        let raw = DockSettings.rawSnapshot()
        guard !raw.isEqual(lastRaw) else { return }
        lastRaw = raw
        reload()
    }

    /// Reloads settings and content, then updates every copy.
    private func reload() {
        settings = DockSettings.load()
        items = DockModel.items(settings: settings)
        layoutWindows()
        updateAutohideTimer()
    }

    @objc func refreshItems() {
        items = DockModel.items(settings: settings)
        layoutWindows()
    }

    /// Recreates one Dock window per target display.
    @objc func rebuildWindows() {
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows = targetScreens.map { _ in DockWindow() }
        reload()
        windows.forEach { $0.orderFrontRegardless() }
    }

    private func layoutWindows() {
        for (window, screen) in zip(windows, targetScreens) {
            window.update(items: items, settings: settings, on: screen)
        }
    }

    private func updateAutohideTimer() {
        if settings.autohide {
            guard autohideTimer == nil else { return }
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                let mouse = NSEvent.mouseLocation
                self?.windows.forEach { $0.autohideTick(mouse: mouse) }
            }
            RunLoop.main.add(t, forMode: .common)
            autohideTimer = t
        } else {
            autohideTimer?.invalidate()
            autohideTimer = nil
        }
    }
}
