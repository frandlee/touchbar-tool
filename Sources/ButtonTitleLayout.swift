import AppKit

// Bound each title so one long label cannot consume the entire application strip.
enum ButtonTitleLayout {
    static func width(for title: String) -> CGFloat {
        let measured = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        return min(124, max(64, ceil(measured) + 24))
    }
}
