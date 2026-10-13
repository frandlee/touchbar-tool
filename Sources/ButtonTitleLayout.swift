import AppKit

// Bound each title so one long label cannot consume the entire application strip.
enum ButtonTitleLayout {
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 24, height: 16), flipped: false) { _ in
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 22, height: 10),
                                       xRadius: 2, yRadius: 2)
            outline.lineWidth = 1.3
            outline.stroke()
            NSColor.black.setFill()
            for x in [4.0, 10.0, 16.0] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 5, width: 4, height: 6),
                             xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Touchbar Tool"
        return image
    }()

    static func width(for title: String) -> CGFloat {
        let measured = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        return min(124, max(64, ceil(measured) + 24))
    }
}
