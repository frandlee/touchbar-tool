import AppKit
import UniformTypeIdentifiers

/// Keeps a draft separate from the live configuration until validation and disk save succeed.
final class ConfigurationEditor: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var titles: [NSTextField] = []
    private var texts: [NSTextField] = []
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
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 490),
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
        root.addArrangedSubview(NSTextField(labelWithString: "每行对应一个 Touch Bar 按钮。保存后立即生效。"))
        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.addRow(with: [NSTextField(labelWithString: "按钮"),
                           NSTextField(labelWithString: "显示标题"),
                           NSTextField(labelWithString: "发送文案")])
        for index in Configuration.fixedIDs.indices {
            let title = NSTextField(string: "")
            let text = NSTextField(string: "")
            title.setAccessibilityLabel("第\(index + 1)个按钮显示标题")
            text.setAccessibilityLabel("第\(index + 1)个按钮发送文案")
            title.widthAnchor.constraint(equalToConstant: 150).isActive = true
            text.widthAnchor.constraint(equalToConstant: 480).isActive = true
            titles.append(title)
            texts.append(text)
            grid.addRow(with: [NSTextField(labelWithString: "按钮 \(index + 1)"), title, text])
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
        for index in titles.indices {
            titles[index].stringValue = profile.buttons[index].title
            texts[index].stringValue = profile.buttons[index].text
        }
        paste.state = profile.pasteAuthorized ? .on : .off
        autoSend.state = profile.shouldAutoSend ? .on : .off
        delay.stringValue = String(profile.sendDelayMilliseconds ?? 400)
        feedback.stringValue = ""
    }
    private func captureSelected() throws {
        guard window?.makeFirstResponder(nil) == true,
              let milliseconds = Int(delay.stringValue.trimmingCharacters(in: .whitespaces)) else {
            throw NSError(domain: "Configuration", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "延迟必须是200～1500之间的整数。"])
        }
        let candidate = Configuration(schemaVersion: 2,
            targetBundleIdentifier: drafts[selected].targetBundleIdentifier,
            buttons: Configuration.fixedIDs.indices.map {
                ButtonConfiguration(id: Configuration.fixedIDs[$0], title: titles[$0].stringValue, text: texts[$0].stringValue)
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
