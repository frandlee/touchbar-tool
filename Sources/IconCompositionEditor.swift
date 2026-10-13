import AppKit

final class IconCompositionEditor: NSObject {
    private var panel: NSPanel!
    private var items: [IconSelection] = []
    private var choices: [ButtonIcon] = []
    private let rows = NSStackView()
    private let preview = NSImageView()
    private var iconFields: [NSPopUpButton] = []
    private var colorFields: [NSPopUpButton] = []
    private var completion: (([IconSelection]) -> Void)?

    func present(on parent: NSWindow, items: [IconSelection], completion: @escaping ([IconSelection]) -> Void) {
        self.items = items; self.completion = completion
        choices = ButtonIcon.singleCases + IconLibrary.icons
        for item in items where !choices.contains(item.icon) { choices.append(item.icon) }
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 630, height: 350),
            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "编辑图标组合"
        panel.isReleasedWhenClosed = false
        preview.frame = NSRect(x: 20, y: 288, width: 590, height: 40)
        preview.imageScaling = .scaleProportionallyDown
        preview.contentTintColor = .labelColor
        panel.contentView!.addSubview(preview)
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 8
        rows.frame = NSRect(x: 20, y: 85, width: 590, height: 195)
        panel.contentView!.addSubview(rows)
        let add = NSButton(title: "增加图标", target: self, action: #selector(addIcon))
        add.frame = NSRect(x: 20, y: 20, width: 110, height: 30)
        panel.contentView!.addSubview(add)
        let apply = NSButton(title: "应用到草稿", target: self, action: #selector(apply))
        apply.frame = NSRect(x: 340, y: 20, width: 135, height: 30)
        panel.contentView!.addSubview(apply)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 490, y: 20, width: 110, height: 30)
        panel.contentView!.addSubview(cancel)
        rebuild()
        parent.beginSheet(panel)
    }
    var usedIcons: Set<ButtonIcon> {
        guard panel?.sheetParent != nil else { return [] }
        return Set(iconFields.map { choices[$0.indexOfSelectedItem] })
    }
    private func capture() {
        items = iconFields.indices.map {
            IconSelection(icon: choices[iconFields[$0].indexOfSelectedItem],
                          color: IconColor.allCases[colorFields[$0].indexOfSelectedItem])
        }
    }
    private func rebuild() {
        for row in rows.arrangedSubviews { rows.removeArrangedSubview(row); row.removeFromSuperview() }
        iconFields.removeAll(); colorFields.removeAll()
        for (index, item) in items.enumerated() {
            let icon = NSPopUpButton()
            for choice in choices { icon.menu?.addItem(NSMenuItem(title: IconLibrary.label(for: choice), action: nil, keyEquivalent: "")) }
            icon.selectItem(at: choices.firstIndex(of: item.icon)!)
            icon.widthAnchor.constraint(equalToConstant: 230).isActive = true
            icon.target = self; icon.action = #selector(changed)
            let color = NSPopUpButton()
            color.addItems(withTitles: IconColor.allCases.map(\.label))
            color.selectItem(at: IconColor.allCases.firstIndex(of: item.color)!)
            color.widthAnchor.constraint(equalToConstant: 110).isActive = true
            color.target = self; color.action = #selector(changed)
            iconFields.append(icon); colorFields.append(color)
            let left = NSButton(title: "←", target: self, action: #selector(moveLeft(_:)))
            left.tag = index; left.isEnabled = index > 0
            let right = NSButton(title: "→", target: self, action: #selector(moveRight(_:)))
            right.tag = index; right.isEnabled = index < items.count - 1
            let remove = NSButton(title: "移除", target: self, action: #selector(removeIcon(_:)))
            remove.tag = index
            rows.addArrangedSubview(NSStackView(views: [icon, color, left, right, remove]))
        }
        preview.image = ButtonIconImage.image(for: items, forPreview: true)
        preview.setAccessibilityLabel(items.isEmpty ? "纯文字，无图标" : "图标组合预览")
    }
    @objc private func changed() { capture(); preview.image = ButtonIconImage.image(for: items, forPreview: true) }
    @objc private func addIcon() {
        capture(); guard items.count < 4 else { return }
        items.append(IconSelection(icon: .push, color: .automatic)); rebuild()
    }
    @objc private func removeIcon(_ sender: NSButton) { capture(); items.remove(at: sender.tag); rebuild() }
    @objc private func moveLeft(_ sender: NSButton) { capture(); items.swapAt(sender.tag, sender.tag - 1); rebuild() }
    @objc private func moveRight(_ sender: NSButton) { capture(); items.swapAt(sender.tag, sender.tag + 1); rebuild() }
    @objc private func apply() { capture(); completion?(items); panel.sheetParent?.endSheet(panel); panel.close() }
    @objc private func cancel() { panel.sheetParent?.endSheet(panel); panel.close() }
}

extension NSPasteboard.PasteboardType {
    static let touchbarIcon = NSPasteboard.PasteboardType("local.touchbar-tool.icon")
}
final class DraggableIconView: NSImageView, NSDraggingSource {
    var icon: ButtonIcon?
    override func mouseDown(with event: NSEvent) {
        guard let icon, let image else { return }
        let pasteboard = NSPasteboardItem()
        guard let data = try? JSONEncoder().encode(icon) else { return }
        pasteboard.setData(data, forType: .touchbarIcon)
        let item = NSDraggingItem(pasteboardWriter: pasteboard)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
final class ButtonIconDropView: NSView {
    var selections: [IconSelection] = [] { didSet { updatePreview() } }
    var onDrop: ((ButtonIcon) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let preview = NSImageView()
    init(number: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 44))
        label.stringValue = "按钮 \(number)"
        label.frame = NSRect(x: 0, y: 25, width: 100, height: 18)
        preview.frame = NSRect(x: 0, y: 2, width: 96, height: 20)
        preview.imageScaling = .scaleProportionallyDown
        preview.contentTintColor = .labelColor
        addSubview(label); addSubview(preview)
        registerForDraggedTypes([.touchbarIcon])
        toolTip = "从图标库拖入图标，最多4个；编辑组合可调整颜色和顺序"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updatePreview() { preview.image = ButtonIconImage.image(for: selections, forPreview: true) }
    private func droppedIcon(_ info: NSDraggingInfo) -> ButtonIcon? {
        IconDropPayload.decode(info.draggingPasteboard.data(forType: .touchbarIcon),
                               currentCount: selections.count, available: ButtonIcon.singleCases + IconLibrary.icons)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { droppedIcon(sender) == nil ? [] : .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { droppedIcon(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let icon = droppedIcon(sender) else { return false }
        onDrop?(icon); return true
    }
}
