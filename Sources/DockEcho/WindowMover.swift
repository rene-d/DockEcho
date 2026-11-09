import AppKit
import ApplicationServices

/// Brings an app's main window to the display whose Dock copy was clicked, when the app has
/// no visible window there. Uses the Accessibility API, so DockEcho must be allowed in
/// System Settings › Privacy & Security › Accessibility; without it, nothing is moved.
enum WindowMover {
    private static var didPrompt = false

    /// True when DockEcho may move windows. Asks for the permission once per run.
    static var isAllowed: Bool {
        if AXIsProcessTrusted() { return true }
        if !didPrompt {
            didPrompt = true
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        return false
    }

    /// Returns false when the app has no usable window yet (nothing was decided).
    @discardableResult
    static func bringIfAbsent(pid: pid_t, to screen: NSScreen) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        let windows = standardWindows(of: app)
        guard !windows.isEmpty else { return false }

        let target = axRect(screen.visibleFrame)
        let full = axRect(screen.frame)
        let alreadyThere = windows.contains { w in
            guard let r = frame(of: w) else { return false }
            return full.contains(CGPoint(x: r.midX, y: r.midY))
        }
        if alreadyThere { return true }

        let main = element(app, kAXMainWindowAttribute).flatMap { m in windows.first { CFEqual($0, m) } }
            ?? element(app, kAXFocusedWindowAttribute).flatMap { f in windows.first { CFEqual($0, f) } }
            ?? windows[0]
        guard let r = frame(of: main) else { return true }

        // Keep the size when it fits, otherwise shrink it to the visible area; then center.
        let size = CGSize(width: min(r.width, target.width), height: min(r.height, target.height))
        if size != r.size { set(main, kAXSizeAttribute, size) }
        set(main, kAXPositionAttribute, CGPoint(x: target.midX - size.width / 2,
                                                y: target.midY - size.height / 2))
        AXUIElementPerformAction(main, kAXRaiseAction as CFString)
        return true
    }

    /// Retries until the app shows a window (just launched, or reopened with no window).
    static func bringWhenReady(pid: pid_t, to screen: NSScreen, attempts: Int = 24) {
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if !bringIfAbsent(pid: pid, to: screen) {
                bringWhenReady(pid: pid, to: screen, attempts: attempts - 1)
            }
        }
    }

    // MARK: Accessibility helpers

    private static func standardWindows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.filter { w in
            string(w, kAXSubroleAttribute) == kAXStandardWindowSubrole as String
                && !bool(w, kAXMinimizedAttribute)
                && !bool(w, "AXFullScreen")
        }
    }

    private static func element(_ e: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func string(_ e: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ e: AXUIElement, _ attr: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private static func frame(of w: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &size) == .success,
              let pos, let size else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &p),
              AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    private static func set(_ w: AXUIElement, _ attr: String, _ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, attr as CFString, v) }
    }

    private static func set(_ w: AXUIElement, _ attr: String, _ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, attr as CFString, v) }
    }

    /// Cocoa coordinates (origin bottom-left of the primary display) → Accessibility
    /// coordinates (origin top-left of the primary display).
    private static func axRect(_ r: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
