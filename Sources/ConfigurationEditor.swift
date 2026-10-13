import AppKit
import UniformTypeIdentifiers

private final class ButtonConfigurationGrid: NSGridView {
    override var isFlipped: Bool { true }
}

/// Keeps a draft separate from the live configuration until validation and disk save succeed.
final class ConfigurationEditor: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var titles: [NSTextField] = []
    var manageIcons: (() -> Void)?
    private var rowIcons: [[IconSelection]] = []
    private var dropViews: [ButtonIconDropView] = []
    private let compositionEditor = IconCompositionEditor()
    private var texts: [NSTextField] = []
    private let grid = ButtonConfigurationGrid()
    private let addButtonControl = NSButton(title: "增加按钮", target: nil, action: nil)
    private var original: Configuration!
    private var drafts: [Configuration] = []
    private var selected = 0
    private let applicationPicker = NSPopUpButton()
    private let removeApplication = NSButton(title: "移除应用", target: nil, action: nil)
    private var saveAction: ((Configuration, Configuration) throws -> Void)?
    private let paste = NSButton(checkboxWithTitle: "允许粘贴", target: nil, action: nil)
    private let autoSend = NSButton(checkboxWithTitle: "验证粘贴后自动回车", target: nil, action: nil)
    private let delay = NSTextField(string: "400")
    private let feedback = NSTextField(wrappingLabelWithString: "")

    func present(configuration: Configuration, save: @escaping (Configuration, Configuration) throws -> Void) {
        // Reopening an existing editor preserves unsaved work.
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        original = configuration
        saveAction = save
        if window == nil { createWindow() }
        drafts = configuration.profiles
        selected = 0
        refreshApplicationPicker()
        loadSelected()
        feedback.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func createWindow() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "编辑配置"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 20)
        ])
        applicationPicker.target = self
        applicationPicker.action = #selector(selectApplication)
        applicationPicker.widthAnchor.constraint(equalToConstant: 460).isActive = true
        let add = NSButton(title: "添加应用…", target: self, action: #selector(addApplication))
        removeApplication.target = self
        removeApplication.action = #selector(removeSelectedApplication)
        root.addArrangedSubview(NSStackView(views: [applicationPicker, add, removeApplication]))
        root.addArrangedSubview(NSTextField(labelWithString: "新应用默认仅粘贴。未配置的应用不显示按钮。"))
        root.addArrangedSubview(NSTextField(labelWithString: "从图标库拖到第一列，或点“编辑组合”。保存后生效。"))
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = grid
        scroll.widthAnchor.constraint(equalToConstant: 860).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 260).isActive = true
        root.addArrangedSubview(scroll)
        addButtonControl.target = self
        addButtonControl.action = #selector(addButton)
        let manage = NSButton(title: "管理图标…", target: self, action: #selector(openIconLibrary))
        root.addArrangedSubview(NSStackView(views: [addButtonControl, manage]))
        let switches = NSStackView(views: [paste, autoSend])
        switches.spacing = 24
        root.addArrangedSubview(switches)
        delay.widthAnchor.constraint(equalToConstant: 70).isActive = true
        root.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: "回车延迟（200～1500 毫秒）"), delay]))
        feedback.textColor = .secondaryLabelColor
        feedback.widthAnchor.constraint(equalToConstant: 750).isActive = true
        root.addArrangedSubview(feedback)
        let save = NSButton(title: "保存并生效", target: self, action: #selector(saveDraft))
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelEditing))
        cancel.keyEquivalent = "\u{1b}"
        root.addArrangedSubview(NSStackView(views: [save, cancel]))
        window = panel
    }

    private func refreshApplicationPicker() {
        applicationPicker.removeAllItems()
        for profile in drafts {
            let identifier = profile.targetBundleIdentifier
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
                .map { $0.deletingPathExtension().lastPathComponent } ?? identifier
            applicationPicker.addItem(withTitle: "\(name) — \(identifier)")
        }
        applicationPicker.selectItem(at: selected)
        removeApplication.isEnabled = drafts.count > 1
    }
    private func loadSelected() {
        let profile = drafts[selected]
        rebuildRows(profile.buttons)
        paste.state = profile.pasteAuthorized ? .on : .off
        autoSend.state = profile.shouldAutoSend ? .on : .off
        delay.stringValue = String(profile.sendDelayMilliseconds ?? 400)
        feedback.stringValue = ""
    }
    private func rebuildRows(_ buttons: [ButtonConfiguration]) {
        while grid.numberOfRows > 0 {
            for column in 0..<grid.numberOfColumns {
                grid.cell(atColumnIndex: column, rowIndex: 0).contentView?.removeFromSuperview()
            }
            grid.removeRow(at: 0)
        }
        titles.removeAll()
        texts.removeAll()
        dropViews.removeAll()
        rowIcons = buttons.map(\.effectiveIcons)
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.addRow(with: [NSTextField(labelWithString: "按钮"), NSTextField(labelWithString: "显示标题"),
                          NSTextField(labelWithString: "图标"), NSTextField(labelWithString: "发送文案"), NSTextField(labelWithString: "操作")])
        for (index, button) in buttons.enumerated() {
            let title = NSTextField(string: button.title)
            let text = NSTextField(string: button.text)
            title.setAccessibilityLabel("第\(index + 1)个按钮显示标题")
            text.setAccessibilityLabel("第\(index + 1)个按钮发送文案")
            title.widthAnchor.constraint(equalToConstant: 150).isActive = true
            text.widthAnchor.constraint(equalToConstant: 360).isActive = true
            let remove = NSButton(title: "删除", target: self, action: #selector(removeButton(_:)))
            remove.tag = index
            remove.isEnabled = buttons.count > 1
            remove.setAccessibilityLabel("删除按钮\(index + 1)")
            let picker = NSButton(title: "编辑组合…", target: self, action: #selector(editIconComposition(_:)))
            picker.tag = index
            picker.widthAnchor.constraint(equalToConstant: 100).isActive = true
            let drop = ButtonIconDropView(number: index + 1)
            drop.widthAnchor.constraint(equalToConstant: 100).isActive = true
            drop.heightAnchor.constraint(equalToConstant: 44).isActive = true
            drop.selections = rowIcons[index]
            drop.onDrop = { [weak self] icon in
                guard let self, self.rowIcons.indices.contains(index), self.rowIcons[index].count < 4 else { return }
                self.rowIcons[index].append(IconSelection(icon: icon, color: .automatic))
                self.dropViews[index].selections = self.rowIcons[index]
            }
            dropViews.append(drop)
            titles.append(title)
            texts.append(text)
            grid.addRow(with: [drop, title, picker, text, remove])
        }
        grid.layoutSubtreeIfNeeded()
        grid.setFrameSize(grid.fittingSize)
        addButtonControl.isEnabled = buttons.count < Configuration.maximumButtons
    }
    private func replaceButtons(_ buttons: [ButtonConfiguration]) {
        let old = drafts[selected]
        drafts[selected] = Configuration(schemaVersion: old.schemaVersion, targetBundleIdentifier: old.targetBundleIdentifier,
            buttons: buttons, pasteAuthorized: old.pasteAuthorized, autoSend: old.autoSend,
            sendDelayMilliseconds: old.sendDelayMilliseconds)
        rebuildRows(buttons)
    }
    @objc private func addButton() {
        do {
            try captureSelected()
            var buttons = drafts[selected].buttons
            guard buttons.count < Configuration.maximumButtons else { return }
            let label = "按钮\(buttons.count + 1)"
            buttons.append(ButtonConfiguration(id: UUID().uuidString, title: label, text: label))
            replaceButtons(buttons)
            feedback.stringValue = "保存后生效。"
        } catch { feedback.stringValue = (error as NSError).localizedDescription }
    }
    @objc private func removeButton(_ sender: NSButton) {
        guard drafts[selected].buttons.count > 1, drafts[selected].buttons.indices.contains(sender.tag) else { return }
        // Allow removal of an invalid row while preserving edits in every retained row.
        guard window?.makeFirstResponder(nil) == true else { return }
        var buttons = drafts[selected].buttons
        for index in buttons.indices where index != sender.tag {
            buttons[index] = ButtonConfiguration(id: buttons[index].id, title: titles[index].stringValue, text: texts[index].stringValue, icons: rowIcons[index])
        }
        buttons.remove(at: sender.tag)
        replaceButtons(buttons)
        feedback.stringValue = "保存后生效。"
    }
    @objc private func openIconLibrary() { manageIcons?() }
    var usedIcons: Set<ButtonIcon> {
        guard window?.isVisible == true else { return [] }
        var result = Set(drafts.flatMap { $0.buttons.flatMap { $0.effectiveIcons.map(\.icon) } })
        for values in rowIcons { result.formUnion(values.map(\.icon)) }
        result.formUnion(compositionEditor.usedIcons)
        return result
    }
    func refreshIconChoices() {
        for (index, view) in dropViews.enumerated() { view.selections = rowIcons[index] }
    }
    @objc private func editIconComposition(_ sender: NSButton) {
        guard let window, rowIcons.indices.contains(sender.tag) else { return }
        let index = sender.tag
        compositionEditor.present(on: window, items: rowIcons[index]) { [weak self] values in
            guard let self, self.rowIcons.indices.contains(index) else { return }
            self.rowIcons[index] = values
            self.dropViews[index].selections = values
        }
    }
    private func captureSelected() throws {
        guard window?.makeFirstResponder(nil) == true,
              let milliseconds = Int(delay.stringValue.trimmingCharacters(in: .whitespaces)) else {
            throw NSError(domain: "Configuration", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "延迟必须是200～1500之间的整数。"])
        }
        let candidate = Configuration(schemaVersion: 2,
            targetBundleIdentifier: drafts[selected].targetBundleIdentifier,
            buttons: titles.indices.map {
                ButtonConfiguration(id: drafts[selected].buttons[$0].id, title: titles[$0].stringValue, text: texts[$0].stringValue, icons: rowIcons[$0])
            }, pasteAuthorized: paste.state == .on, autoSend: autoSend.state == .on,
            sendDelayMilliseconds: milliseconds)
        try candidate.validate()
        drafts[selected] = candidate
    }
    @objc private func selectApplication() {
        let next = applicationPicker.indexOfSelectedItem
        do {
            try captureSelected()
            selected = next
            loadSelected()
        } catch {
            applicationPicker.selectItem(at: selected)
            feedback.stringValue = (error as NSError).localizedDescription
        }
    }
    @objc private func addApplication() {
        do { try captureSelected() }
        catch { feedback.stringValue = (error as NSError).localizedDescription; return }
        let chooser = NSOpenPanel()
        chooser.title = "选择要配置的应用"
        chooser.directoryURL = URL(fileURLWithPath: "/Applications")
        chooser.allowedContentTypes = [.application]
        chooser.allowsMultipleSelection = false
        chooser.canChooseDirectories = false
        guard chooser.runModal() == .OK, let url = chooser.url,
              let identifier = Bundle(url: url)?.bundleIdentifier else { return }
        if let existing = drafts.firstIndex(where: { $0.targetBundleIdentifier == identifier }) {
            selected = existing
        } else {
            let labels = ["按钮1", "按钮2", "按钮3", "按钮4", "按钮5"]
            drafts.append(Configuration(schemaVersion: 2, targetBundleIdentifier: identifier,
                buttons: Configuration.fixedIDs.indices.map {
                    ButtonConfiguration(id: Configuration.fixedIDs[$0], title: labels[$0], text: labels[$0])
                }, pasteAuthorized: true, autoSend: false, sendDelayMilliseconds: 400))
            selected = drafts.count - 1
        }
        refreshApplicationPicker()
        loadSelected()
    }
    @objc private func removeSelectedApplication() {
        guard drafts.count > 1 else { return }
        drafts.remove(at: selected)
        selected = min(selected, drafts.count - 1)
        refreshApplicationPicker()
        loadSelected()
        feedback.stringValue = "保存后将移除此应用的配置。"
    }
    @objc private func saveDraft() {
        do {
            try captureSelected()
            let candidate = Configuration.combining(drafts)
            try candidate.validate()
            try saveAction?(candidate, original)
            original = candidate
            feedback.stringValue = "已保存并生效。"
        } catch {
            feedback.stringValue = "保存失败：\((error as NSError).localizedDescription)"
        }
    }
    @objc private func cancelEditing() { window?.close() }
}
