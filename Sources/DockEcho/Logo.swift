import AppKit

/// The DockEcho logo, drawn in code: a gradient app icon with a glass dock bar and its "echoes".
enum Logo {
    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let r = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
            let body = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)

            // Background gradient + soft highlight
            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            NSGradient(colorsAndLocations:
                        (NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1), 0.0),
                       (NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 1), 0.55),
                       (NSColor(srgbRed: 1.00, green: 0.22, blue: 0.37, alpha: 1), 1.0))?
                .draw(in: r, angle: -45)
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.25), NSColor.clear])?
                .draw(in: NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2), angle: -90)
            NSGraphicsContext.restoreGraphicsState()

            func bar(width: CGFloat, height: CGFloat, y: CGFloat, alpha: CGFloat) -> NSRect {
                let rect = NSRect(x: r.midX - width / 2, y: y, width: width, height: height)
                let path = NSBezierPath(roundedRect: rect, xRadius: height * 0.34, yRadius: height * 0.34)
                NSColor.white.withAlphaComponent(alpha).setFill()
                path.fill()
                NSColor.white.withAlphaComponent(min(1, alpha + 0.2)).setStroke()
                path.lineWidth = max(1, r.width * 0.006)
                path.stroke()
                return rect
            }

            // The real dock and its two fading echoes
            let h = r.height * 0.25
            let main = bar(width: r.width * 0.72, height: h, y: r.minY + r.height * 0.12, alpha: 0.32)
            let e1 = bar(width: r.width * 0.56, height: h * 0.8, y: main.maxY + h * 0.14, alpha: 0.18)
            _ = bar(width: r.width * 0.40, height: h * 0.64, y: e1.maxY + h * 0.12, alpha: 0.09)

            // Tiny app tiles inside the main bar
            let tile = h * 0.62
            let gap = (main.width - 4 * tile) / 5
            let colors: [NSColor] = [.white, .systemGreen, .systemYellow, .systemTeal]
            for (i, c) in colors.enumerated() {
                let t = NSRect(x: main.minX + gap + CGFloat(i) * (tile + gap),
                               y: main.midY - tile / 2, width: tile, height: tile)
                c.withAlphaComponent(0.92).setFill()
                NSBezierPath(roundedRect: t, xRadius: tile * 0.24, yRadius: tile * 0.24).fill()
            }
            return true
        }
    }
}
