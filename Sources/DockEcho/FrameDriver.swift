import AppKit
import QuartzCore

/// Calls `onFrame(dt)` once per display refresh (CADisplayLink, so it follows the
/// screen's real refresh rate, including 120 Hz). `onFrame` returns false to stop.
final class FrameDriver: NSObject {
    weak var view: NSView?
    var onFrame: ((CGFloat) -> Bool)?

    private var link: AnyObject?
    private var timer: Timer?
    private var last: CFTimeInterval = 0

    var isRunning: Bool { link != nil || timer != nil }

    func start() {
        guard !isRunning, let view else { return }
        last = CACurrentMediaTime()
        if #available(macOS 14.0, *) {
            let l = view.displayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        } else {
            let t = Timer(timeInterval: 1.0 / 120.0, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    func stop() {
        if #available(macOS 14.0, *) { (link as? CADisplayLink)?.invalidate() }
        link = nil
        timer?.invalidate()
        timer = nil
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - last, 0.05))
        last = now
        if onFrame?(dt) == false { stop() }
    }

    deinit { stop() }
}
