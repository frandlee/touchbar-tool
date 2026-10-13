import AppKit

// Bound each title so one long label cannot consume the entire application strip.
enum ButtonTitleLayout {
    private static let chineseJapaneseIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 48, height: 22), flipped: false) { bounds in
            let text = NSAttributedString(string: "中⇄日", attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.black
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                  y: (bounds.height - size.height) / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "中日翻译"
        return image
    }()

    static func icon(for title: String) -> NSImage? {
        title == "中日翻译" ? chineseJapaneseIcon : nil
    }

    static func width(for title: String) -> CGFloat {
        let measured = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        return min(124, max(64, ceil(measured) + 24))
    }
}
