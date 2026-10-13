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


enum ButtonIconImage {
    static func image(for selections: [IconSelection], forPreview: Bool = false) -> NSImage? {
        guard !selections.isEmpty, selections.count <= 4 else { return nil }
        let sources = selections.compactMap { image(for: $0.icon) }
        guard sources.count == selections.count else { return nil }
        let template = selections.allSatisfy {
            if case .custom = $0.icon { return false }
            return $0.color == .automatic
        }
        let size = NSSize(width: selections.count * 26 - 6, height: 20)
        let result = NSImage(size: size, flipped: false) { _ in
            for (index, source) in sources.enumerated() {
                let selection = selections[index]
                let color: NSColor?
                switch selection.color {
                case .automatic:
                    if case .custom = selection.icon { color = nil }
                    else { color = template ? .black : (forPreview ? .labelColor : .white) }
                case .blue: color = .systemBlue
                case .green: color = .systemGreen
                case .purple: color = .systemPurple
                case .orange: color = .systemOrange
                case .teal: color = .systemTeal
                case .red: color = .systemRed
                }
                let layer = NSImage(size: NSSize(width: 20, height: 20))
                layer.lockFocus()
                source.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20))
                if let color {
                    color.setFill()
                    NSRect(x: 0, y: 0, width: 20, height: 20).fill(using: .sourceIn)
                }
                layer.unlockFocus()
                layer.draw(in: NSRect(x: index * 26, y: 0, width: 20, height: 20))
            }
            return true
        }
        result.isTemplate = template
        return result
    }
    private static var cache: [ButtonIcon: NSImage] = [:]
    static func image(for icon: ButtonIcon?) -> NSImage? {
        guard let icon else { return nil }
        if case .custom(let id) = icon {
            guard UUID(uuidString: id) != nil,
                  let image = NSImage(contentsOf: IconLibrary.directory.appendingPathComponent(id + ".png")) else { return nil }
            image.size = NSSize(width: 20, height: 20)
            return image // Imported artwork retains its colors.
        }
        if let cached = cache[icon] { return cached }
        let names: [String]
        switch icon {
        case .custom: return nil
        case .push: names = ["repo-push"]
        case .merge: names = ["git-merge"]
        case .deploy: names = ["rocket"]
        case .pushMergeDeploy: names = ["repo-push", "git-merge", "rocket"]
        }
        var images: [NSImage] = []
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Octicons"),
                  let image = NSImage(contentsOf: url) else { return nil }
            images.append(image)
        }
        let size = NSSize(width: CGFloat(names.count * 20 + (names.count - 1) * 6), height: 20)
        let result = NSImage(size: size, flipped: false) { _ in
            for (index, image) in images.enumerated() {
                image.draw(in: NSRect(x: CGFloat(index * 26), y: 0, width: 20, height: 20))
            }
            return true
        }
        result.isTemplate = true
        cache[icon] = result
        return result
    }
}


enum IconLibrary {
    static var directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("touchbar-icons")
    static var icons: [ButtonIcon] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "png" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .map { ButtonIcon.custom($0.deletingPathExtension().lastPathComponent) }
            .sorted { label(for: $0).localizedStandardCompare(label(for: $1)) == .orderedAscending }
    }
    static func label(for icon: ButtonIcon) -> String {
        guard case .custom(let id) = icon else { return icon.label }
        return (try? String(contentsOf: directory.appendingPathComponent(id + ".name"), encoding: .utf8)) ?? "自定义图标"
    }
    static func importImage(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? Int.max) <= 5_000_000,
              let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0,
              image.size.width <= 8192, image.size.height <= 8192 else {
            throw NSError(domain: "IconLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择不超过5MB、8192像素的有效图片。"])
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = min(128 / image.size.width, 128 / image.size.height)
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        image.draw(in: NSRect(x: (128 - size.width) / 2, y: (128 - size.height) / 2, width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        try data.write(to: directory.appendingPathComponent(id + ".png"), options: .atomic)
        try url.deletingPathExtension().lastPathComponent.write(to: directory.appendingPathComponent(id + ".name"), atomically: true, encoding: .utf8)
    }
    static func remove(_ icon: ButtonIcon) throws {
        guard case .custom(let id) = icon, UUID(uuidString: id) != nil else { return }
        try FileManager.default.trashItem(at: directory.appendingPathComponent(id + ".png"), resultingItemURL: nil)
        try? FileManager.default.trashItem(at: directory.appendingPathComponent(id + ".name"), resultingItemURL: nil)
    }
}
