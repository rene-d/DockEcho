import AppKit

struct DockItem {
    enum Kind { case app, folder, trash, separator, spacer }
    let id: String
    let url: URL
    let name: String
    let isRunning: Bool
    let kind: Kind

    var isTile: Bool { kind == .app || kind == .folder || kind == .trash }
}

extension Notification.Name {
    static let dockBounce = Notification.Name("DockEchoBounce")
}

/// Whether the Trash currently contains something (to pick the right icon).
enum TrashState {
    private(set) static var isFull = false

    /// Returns true if the state changed.
    /// Reading ~/.Trash requires Full Disk Access; without it the Trash is assumed empty.
    @discardableResult
    static func refresh() -> Bool {
        let path = NSHomeDirectory() + "/.Trash"
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        let full = contents.contains { $0 != ".DS_Store" }
        let changed = full != isFull
        isFull = full
        return changed
    }
}

enum DockModel {
    private static let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    private static func entries(_ key: String) -> [[String: Any]] {
        DockSettings.value(key) as? [[String: Any]] ?? []
    }

    private static func tile(_ entry: [String: Any]) -> (url: URL, label: String?)? {
        guard let tile = entry["tile-data"] as? [String: Any],
              let file = tile["file-data"] as? [String: Any],
              let str = file["_CFURLString"] as? String,
              let url = URL(string: str),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url, tile["file-label"] as? String)
    }

    static func items(settings: DockSettings) -> [DockItem] {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        let runningIDs = Set(running.compactMap { $0.bundleIdentifier })

        var result: [DockItem] = []
        var seen = Set<String>()
        var counter = 0

        func addApp(_ url: URL) {
            let id = Bundle(url: url)?.bundleIdentifier ?? url.path
            guard seen.insert(id).inserted else { return }
            result.append(DockItem(id: id, url: url,
                                   name: FileManager.default.displayName(atPath: url.path),
                                   isRunning: runningIDs.contains(id), kind: .app))
        }
        func addDivider(_ kind: DockItem.Kind) {
            counter += 1
            result.append(DockItem(id: "divider-\(counter)", url: finderURL, name: "",
                                   isRunning: false, kind: kind))
        }

        // 1. Applications
        addApp(finderURL)
        if settings.staticOnly {
            // "Show only open applications"
            for app in running { if let url = app.bundleURL { addApp(url) } }
        } else {
            for entry in entries("persistent-apps") {
                if let type = entry["tile-type"] as? String, type.contains("spacer") {
                    addDivider(.spacer)
                } else if let t = tile(entry) {
                    addApp(t.url)
                }
            }
            for app in running { if let url = app.bundleURL { addApp(url) } }
        }

        // 2. Recent apps
        if settings.showRecents && !settings.staticOnly {
            var recents: [DockItem] = []
            for entry in entries("recent-apps") {
                guard recents.count < 3, let t = tile(entry) else { continue }
                let id = Bundle(url: t.url)?.bundleIdentifier ?? t.url.path
                guard seen.insert(id).inserted else { continue }
                recents.append(DockItem(id: id, url: t.url,
                                        name: FileManager.default.displayName(atPath: t.url.path),
                                        isRunning: false, kind: .app))
            }
            if !recents.isEmpty {
                addDivider(.separator)
                result += recents
            }
        }

        // 3. Folders / files (persistent-others), then the Trash
        addDivider(.separator)
        for entry in entries("persistent-others") {
            guard let t = tile(entry) else { continue }
            result.append(DockItem(id: t.url.path, url: t.url,
                                   name: t.label ?? FileManager.default.displayName(atPath: t.url.path),
                                   isRunning: false, kind: .folder))
        }
        result.append(DockItem(id: "trash", url: URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"),
                               name: "Trash", isRunning: false, kind: .trash))
        return result
    }
}

enum IconCache {
    private static var images: [String: NSImage] = [:]
    private static var rasters: [String: CGImage] = [:]

    private static func key(_ item: DockItem) -> String {
        item.kind == .trash ? (TrashState.isFull ? "trash-full" : "trash-empty") : item.url.path
    }

    static func image(for item: DockItem) -> NSImage {
        let k = key(item)
        if let img = images[k] { return img }
        let img = load(item)
        images[k] = img
        return img
    }

    private static func load(_ item: DockItem) -> NSImage {
        guard item.kind == .trash else { return NSWorkspace.shared.icon(forFile: item.url.path) }
        // The real Trash icons shipped with macOS; fall back to the named system images.
        let name = TrashState.isFull ? "FullTrashIcon" : "TrashIcon"
        let path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/\(name).icns"
        if let img = NSImage(contentsOfFile: path) { return img }
        if let img = NSImage(named: TrashState.isFull ? NSImage.trashFullName : NSImage.trashEmptyName) { return img }
        return NSWorkspace.shared.icon(forFile: item.url.path)
    }

    /// A bitmap rendered once at the largest size the icon can reach; the GPU scales it
    /// down while the Dock magnifies, so no redrawing is needed during animations.
    static func raster(for item: DockItem, points: CGFloat, scale: CGFloat) -> CGImage? {
        let px = Int((points * scale).rounded())
        let k = "\(key(item))@\(px)"
        if let cg = rasters[k] { return cg }
        var rect = NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px))
        let cg = image(for: item).cgImage(forProposedRect: &rect, context: nil, hints: nil)
        rasters[k] = cg
        return cg
    }
}

enum DockActions {
    static func runningApp(for item: DockItem) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: item.id).first
    }

    static func activate(_ item: DockItem) {
        switch item.kind {
        case .trash, .folder:
            NSWorkspace.shared.open(item.url)
        case .app:
            if let app = runningApp(for: item) {
                app.unhide()
                app.activate(options: [.activateAllWindows])
            } else {
                NotificationCenter.default.post(name: .dockBounce, object: item.id)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: item.url, configuration: config)
            }
        case .separator, .spacer:
            break
        }
    }
}
