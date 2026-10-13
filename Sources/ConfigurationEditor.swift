import AppKit

/// Keeps a draft separate from the live configuration until validation and disk save succeed.
final class ConfigurationEditor: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var titles: [NSTextField] = []
    private var texts: [NSTextField] = []
    private var original: Configuration!
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
        for index in titles.indices {
            titles[index].stringValue = configuration.buttons[index].title
            texts[index].stringValue = configuration.buttons[index].text
        }
        paste.state = configuration.pasteAuthorized ? .on : .off
        autoSend.state = configuration.shouldAutoSend ? .on : .off
        delay.stringValue = String(configuration.sendDelayMilliseconds ?? 400)
        feedback.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func createWindow() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 420),
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
        root.addArrangedSubview(NSTextField(labelWithString: "每行对应一个 Touch Bar 按钮。保存后立即生效。"))
        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.addRow(with: [NSTextField(labelWithString: "按钮"),
                           NSTextField(labelWithString: "显示标题"),
                           NSTextField(labelWithString: "发送文案")])
        for (index, id) in Configuration.fixedIDs.enumerated() {
            let title = NSTextField(string: "")
            let text = NSTextField(string: "")
            title.setAccessibilityLabel("第\(index + 1)个按钮显示标题")
            text.setAccessibilityLabel("第\(index + 1)个按钮发送文案")
            title.widthAnchor.constraint(equalToConstant: 150).isActive = true
            text.widthAnchor.constraint(equalToConstant: 480).isActive = true
            titles.append(title)
            texts.append(text)
            grid.addRow(with: [NSTextField(labelWithString: "\(index + 1). \(id)"), title, text])
        }
        root.addArrangedSubview(grid)
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

    @objc private func saveDraft() {
        // Commit the active field editor before collecting the draft.
        guard window?.makeFirstResponder(nil) == true else { return }
        guard let milliseconds = Int(delay.stringValue.trimmingCharacters(in: .whitespaces)) else {
            feedback.stringValue = "延迟必须是200～1500之间的整数。"
            return
        }
        let candidate = Configuration(schemaVersion: original.schemaVersion,
            targetBundleIdentifier: original.targetBundleIdentifier,
            buttons: Configuration.fixedIDs.indices.map {
                ButtonConfiguration(id: Configuration.fixedIDs[$0], title: titles[$0].stringValue, text: texts[$0].stringValue)
            }, pasteAuthorized: paste.state == .on, autoSend: autoSend.state == .on,
            sendDelayMilliseconds: milliseconds)
        do {
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
