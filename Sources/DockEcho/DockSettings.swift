import AppKit

enum DockOrientation: String {
    case bottom, left, right
}

/// Settings of the real Dock (System Settings > Desktop & Dock), read from com.apple.dock.
struct DockSettings: Equatable {
    var tileSize: CGFloat = 64                 // tilesize
    var magnification = false                  // magnification
    var largeSize: CGFloat = 128               // largesize
    var orientation: DockOrientation = .bottom // orientation
    var autohide = false                       // autohide
    var autohideDelay: Double = 0.5            // autohide-delay
    var autohideTimeModifier: Double = 1.0     // autohide-time-modifier
    var showIndicators = true                  // show-process-indicators
    var showRecents = true                     // show-recents
    var staticOnly = false                     // static-only
    var launchAnimation = true                 // launchanim

    var maxScale: CGFloat {
        magnification ? min(3, max(1, largeSize / tileSize)) : 1
    }

    // MARK: Reading the preferences

    private static let appID = "com.apple.dock" as CFString

    private static let keys = [
        "tilesize", "magnification", "largesize", "orientation", "autohide",
        "autohide-delay", "autohide-time-modifier", "show-process-indicators",
        "show-recents", "static-only", "launchanim",
        "persistent-apps", "persistent-others", "recent-apps"
    ]

    static func value(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, appID)
    }

    /// Raw snapshot of every relevant key: used to detect changes.
    static func rawSnapshot() -> NSDictionary {
        CFPreferencesAppSynchronize(appID)
        let d = NSMutableDictionary()
        for k in keys {
            if let v = value(k) { d[k] = v }
        }
        return d
    }

    static func load() -> DockSettings {
        CFPreferencesAppSynchronize(appID)
        var s = DockSettings()

        func num(_ k: String) -> Double? { (value(k) as? NSNumber)?.doubleValue }
        func flag(_ k: String) -> Bool? { (value(k) as? NSNumber)?.boolValue }

        if let v = num("tilesize") { s.tileSize = CGFloat(min(max(v, 16), 128)) }
        if let v = num("largesize") { s.largeSize = CGFloat(min(max(v, 16), 128)) }
        s.largeSize = max(s.largeSize, s.tileSize)
        s.magnification = flag("magnification") ?? false
        if let o = value("orientation") as? String, let ori = DockOrientation(rawValue: o) {
            s.orientation = ori
        }
        s.autohide = flag("autohide") ?? false
        s.autohideDelay = max(0, num("autohide-delay") ?? 0.5)
        s.autohideTimeModifier = max(0, num("autohide-time-modifier") ?? 1.0)
        s.showIndicators = flag("show-process-indicators") ?? true
        s.showRecents = flag("show-recents") ?? true
        s.staticOnly = flag("static-only") ?? false
        s.launchAnimation = flag("launchanim") ?? true
        return s
    }
}
