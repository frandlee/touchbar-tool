import AppKit
import UniformTypeIdentifiers

private final class IconListView: NSView { override var isFlipped: Bool { true } }

final class IconLibraryWindow: NSObject {
    private var window: NSWindow?
    private let list = IconListView()
    private let message = NSTextField(wrappingLabelWithString: "")
    private var entries: [ButtonIcon] = []
    private var names: [Int: NSTextField] = [:]
    var usedIcons: () -> Set<ButtonIcon> = { [] }
    var didChange: () -> Void = {}

    func present() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "管理图标"
            panel.isReleasedWhenClosed = false
            panel.center()
            let note = NSTextField(labelWithString: "图标库由所有应用共享。拖到配置第一列；自定义图标可重命名或删除。")
            note.frame = NSRect(x: 20, y: 460, width: 610, height: 24)
            panel.contentView!.addSubview(note)
            let scroll = NSScrollView(frame: NSRect(x: 20, y: 90, width: 610, height: 360))
            scroll.hasVerticalScroller = true
            scroll.documentView = list
            panel.contentView!.addSubview(scroll)
            let add = NSButton(title: "导入图标…", target: self, action: #selector(importIcons))
            add.frame = NSRect(x: 20, y: 45, width: 130, height: 30)
            panel.contentView!.addSubview(add)
            message.frame = NSRect(x: 20, y: 10, width: 610, height: 32)
            panel.contentView!.addSubview(message)
            window = panel
        }
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    private func reload() {
        for view in list.subviews { view.removeFromSuperview() }
        names.removeAll()
        entries = ButtonIcon.singleCases + IconLibrary.icons
        list.frame = NSRect(x: 0, y: 0, width: 590, height: CGFloat(entries.count * 44))
        for (index, icon) in entries.enumerated() {
            let y = CGFloat(index * 44)
            let preview = DraggableIconView(frame: NSRect(x: 4, y: y + 5, width: 76, height: 30))
            preview.icon = icon
            preview.toolTip = "拖到配置表格第一列添加图标"
            preview.image = ButtonIconImage.image(for: icon)
            preview.contentTintColor = .labelColor
            preview.imageScaling = .scaleProportionallyDown
            list.addSubview(preview)
            let name = NSTextField(string: IconLibrary.label(for: icon))
            name.frame = NSRect(x: 90, y: y + 8, width: 275, height: 25)
            list.addSubview(name)
            if case .custom = icon {
                names[index] = name
                let rename = NSButton(title: "重命名", target: self, action: #selector(renameIcon(_:)))
                rename.tag = index; rename.frame = NSRect(x: 375, y: y + 5, width: 85, height: 30)
                list.addSubview(rename)
                let remove = NSButton(title: "删除", target: self, action: #selector(removeIcon(_:)))
                remove.tag = index; remove.frame = NSRect(x: 470, y: y + 5, width: 85, height: 30)
                remove.isEnabled = !usedIcons().contains(icon)
                remove.toolTip = "正在被配置或草稿使用的图标不能删除"
                list.addSubview(remove)
            } else { name.isEditable = false; name.isBezeled = false; name.drawsBackground = false }
        }
    }
    @objc private func importIcons() {
        let chooser = NSOpenPanel()
        chooser.title = "导入本地图标"
        chooser.allowedContentTypes = [.png, .jpeg]
        chooser.allowsMultipleSelection = true
        guard chooser.runModal() == .OK else { return }
        var count = 0
        do {
            for url in chooser.urls { try IconLibrary.importImage(url); count += 1 }
            message.stringValue = "已导入\(count)个图标，仅保存在本机。"
        } catch { message.stringValue = "已导入\(count)个；\((error as NSError).localizedDescription)" }
        didChange(); reload()
    }
    @objc private func renameIcon(_ sender: NSButton) {
        guard entries.indices.contains(sender.tag), case .custom(let id) = entries[sender.tag],
              let field = names[sender.tag] else { return }
        window?.makeFirstResponder(nil)
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 80 else { message.stringValue = "名称需为1～80个字符。"; return }
        do {
            try value.write(to: IconLibrary.directory.appendingPathComponent(id + ".name"), atomically: true, encoding: .utf8)
            didChange(); reload(); message.stringValue = "名称已更新。"
        } catch { message.stringValue = (error as NSError).localizedDescription }
    }
    @objc private func removeIcon(_ sender: NSButton) {
        guard entries.indices.contains(sender.tag) else { return }
        let icon = entries[sender.tag]
        guard !usedIcons().contains(icon) else { message.stringValue = "此图标正在使用，请先解除按钮的引用并保存。"; return }
        do {
            try IconLibrary.remove(icon)
            didChange(); reload(); message.stringValue = "图标已移到废纸篓。"
        } catch { message.stringValue = (error as NSError).localizedDescription }
    }
}
