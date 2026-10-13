import AppKit
import ApplicationServices

if CommandLine.arguments.contains("--status") {
    let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("runtime-status.json")
    if let data = try? Data(contentsOf: url), let status = String(data: data, encoding: .utf8) {
        print(status)
    } else { print("No recorded runtime status yet.") }
    exit(0)
}

if CommandLine.arguments.contains("--permissions") {
    print("Accessibility trusted: \(AXIsProcessTrusted())")
    print("Event posting permitted: \(CGPreflightPostEventAccess())")
    print("Read-only preflight; no permission request or target UI access.")
    exit(0)
}

if CommandLine.arguments.contains("--probe") {
    print("Private NSTouchBar method signatures available: \(CTBAvailable())")
    print("Probe does not present Touch Bar, request permissions, or inspect another app.")
    exit(CTBAvailable() ? 0 : 2)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private var status: NSStatusItem!
    private let bar = NSTouchBar()
    private let itemIDs = Configuration.fixedIDs.map { NSTouchBarItem.Identifier("local.codex-touchbar." + $0) }
    private var titleWidths: [NSTouchBarItem.Identifier: NSLayoutConstraint] = [:]
    private var config: Configuration!
    private var configurationStore: ConfigurationStore!
    private var configurationEditor: ConfigurationEditor?
    private var configurationInfo: NSMenuItem?
    private var configurationOutcome = "Loaded at startup"
    private var configurationRevision = 1
    private var diagnosticPasteWork: DispatchWorkItem?
    private var shown = false
    private var enabled = true
    private var timer: Timer?
    private var lastPaste = Date.distantPast
    private var diagnosticWindow: NSWindow?
    private var diagnosticLabel: NSTextField?
    private var pasteOutcome = "Not attempted"
    private var focusNotice = "none"
    private var proofStatus = "not checked"
    private var lastRecordedStatus: String?

    private let sendGate = AutoSendGate()
    private var sendTimer: Timer?
    private var focusObserver: AXObserver?
    private var pendingField: AXUIElement?
    private var pendingPID: pid_t?
    private var pendingText: String?
    private var pendingInsertionLocation: Int?
    private var pendingClipboardCount: Int?


    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != getpid() }) {
            NSApplication.shared.terminate(nil); return
        }
        do {
            let env = ProcessInfo.processInfo.environment["CODEX_TOUCHBAR_CONFIG"]
            let url = env.map { URL(fileURLWithPath: $0) }
                ?? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("config.json")
            configurationStore = try ConfigurationStore(url: url)
            config = configurationStore.current
        } catch { fail("Configuration error: \(error.localizedDescription)"); return }
        guard CTBAvailable() else { fail("Private Touch Bar API unavailable; exiting safely."); return }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "CTB"
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "启用 Touch Bar", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggle.target = self; toggle.state = .on; menu.addItem(toggle)
        let info = NSMenuItem(title: config.pasteAuthorized ? (config.shouldAutoSend ? "五按钮：验证粘贴后回车发送" : "五按钮：仅粘贴") : "粘贴：待用户批准（关闭）", action: nil, keyEquivalent: "")
        menu.addItem(info); configurationInfo = info
        let edit = NSMenuItem(title: "编辑配置", action: #selector(editConfiguration), keyEquivalent: "")
        edit.target = self; menu.addItem(edit)
        let reload = NSMenuItem(title: "重新加载配置", action: #selector(reloadConfiguration), keyEquivalent: "")
        reload.target = self; menu.addItem(reload)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Touchbar Tool", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); status.menu = menu
        bar.delegate = self
        bar.defaultItemIdentifiers = itemIDs
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(hideForSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        // Recheck after wake and recover missed activation notifications.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.update() }
        update()
        if CommandLine.arguments.contains("--diagnostics") { showDiagnostics() }
    }
    private func showDiagnostics() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 240),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Touchbar Tool — Diagnostics"
        window.isReleasedWhenClosed = false
        let label = NSTextField(wrappingLabelWithString: "")
        label.frame = NSRect(x: 20, y: 125, width: 580, height: 95)
        window.contentView?.addSubview(label); diagnosticLabel = label
        let field = NSTextView(frame: NSRect(x: 20, y: 72, width: 580, height: 45))
        field.isRichText = false
        field.font = .systemFont(ofSize: 14)
        field.setAccessibilityLabel("Prototype test input (local only)")
        window.contentView?.addSubview(field)
        let toggle = NSButton(title: "切换启用状态", target: self, action: #selector(diagnosticToggle))
        toggle.frame = NSRect(x: 20, y: 25, width: 95, height: 32)
        window.contentView?.addSubview(toggle)
        let paste = NSButton(title: "测试粘贴（仅本应用）", target: self, action: #selector(diagnosticPaste))
        paste.frame = NSRect(x: 120, y: 25, width: 155, height: 32)
        window.contentView?.addSubview(paste)
        let edit = NSButton(title: "编辑配置", target: self, action: #selector(editConfiguration))
        edit.frame = NSRect(x: 280, y: 25, width: 95, height: 32)
        window.contentView?.addSubview(edit)
        let reload = NSButton(title: "重新加载配置", target: self, action: #selector(reloadConfiguration))
        reload.frame = NSRect(x: 380, y: 25, width: 135, height: 32)
        window.contentView?.addSubview(reload)
        let quit = NSButton(title: "退出", target: self, action: #selector(quitApp))
        quit.frame = NSRect(x: 520, y: 25, width: 75, height: 32)
        window.contentView?.addSubview(quit)
        diagnosticWindow = window
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeFirstResponder(field)
        updateDiagnostics()
    }
    private func updateDiagnostics() {
        recordRuntimeStatus()
        diagnosticLabel?.stringValue = "AX trusted: \(AXIsProcessTrusted()); Event posting: \(CGPreflightPostEventAccess())\nEnabled: \(enabled); Paste: \(config.pasteAuthorized); Auto-send: \(config.shouldAutoSend)\nTarget: \(config.targetBundleIdentifier); Frontmost: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")\nButtons: \(config.buttons.map(\.title).joined(separator: "｜")); Presented: \(shown); Paste: \(pasteOutcome); Focus: \(focusNotice); Proof: \(proofStatus)\nConfig #\(configurationRevision): \(configurationOutcome)"
    }
    @objc private func diagnosticToggle() { enabled.toggle(); if !enabled { cancelAutoSend("Cancelled: disabled") }; update() }
    @objc private func diagnosticPaste() {
        // Diagnostic button cannot send to any other application.
        guard config.targetBundleIdentifier == Bundle.main.bundleIdentifier else { return }
        diagnosticWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        diagnosticPasteWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.diagnosticPasteWork = nil
            self.paste(text: self.config.buttons[0].text)
        }
        diagnosticPasteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    @objc private func editConfiguration() {
        cancelAutoSend("Cancelled: edit configuration")
        if configurationEditor == nil {
            configurationEditor = ConfigurationEditor()
        }
        configurationEditor?.present(configuration: config) { [weak self] candidate, expected in
            guard let self else { return }
            try self.configurationStore.save(candidate, expected: expected) {
                self.cancelAutoSend("Cancelled: configuration save")
            }
            self.applyConfiguration(candidate)
        }
    }

    @objc private func reloadConfiguration() {
        do {
            let candidate = try configurationStore.reload { self.cancelAutoSend("Cancelled: configuration reload") }
            applyConfiguration(candidate)
        } catch {
            configurationOutcome = "加载失败，旧配置保留：" + ConfigurationStore.message(for: error)
            updateDiagnostics()
            let alert = NSAlert()
            alert.messageText = "配置未重新加载"
            alert.informativeText = ConfigurationStore.message(for: error) + "\n旧配置继续生效；待发送操作已取消。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "知道了")
            alert.runModal()
        }
    }
    private func applyConfiguration(_ candidate: Configuration) {
        config = candidate
        configurationRevision += 1
        configurationOutcome = "重新加载成功"
        configurationInfo?.title = config.pasteAuthorized ? (config.shouldAutoSend ? "五按钮：验证粘贴后回车发送" : "五按钮：仅粘贴") : "粘贴：待用户批准（关闭）"
        for (index, identifier) in itemIDs.enumerated() {
            if let item = bar.item(forIdentifier: identifier) as? NSCustomTouchBarItem,
               let button = item.view as? NSButton {
                applyButtonTitle(config.buttons[index].title, to: button, identifier: identifier)
                button.isEnabled = config.pasteAuthorized
            }
        }
        update()
    }
    private func fail(_ message: String) {
        fputs(message + "\n", stderr)
        NSApplication.shared.terminate(nil)
    }
    @objc private func update() {
        status?.menu?.items.first?.state = enabled ? .on : .off
        let shouldShow = enabled && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == config.targetBundleIdentifier
        if shouldShow && !shown {
            shown = CTBPresent(bar)
            if !shown { fail("Private Touch Bar presentation failed.") }
        } else if !shouldShow { hide() }
        updateDiagnostics()
    }
    private func hide() {
        guard shown else { return }
        if !CTBDismiss(bar) { fail("Private Touch Bar dismissal failed.") }
        shown = false
    }
    @objc private func activeApplicationChanged(_ notification: Notification) {
        cancelAutoSend("Cancelled: application activation changed")
        update()
    }
    @objc private func hideForSleep() { cancelAutoSend("Cancelled: sleep"); hide() }
    @objc private func toggleEnabled(_ item: NSMenuItem) {
        enabled.toggle(); item.state = enabled ? .on : .off; if !enabled { cancelAutoSend("Cancelled: disabled") }; update()
    }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        cancelAutoSend("Cancelled: exit")
        if shown { _ = CTBDismiss(bar) }
    }
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let index = itemIDs.firstIndex(of: identifier) else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(title: config.buttons[index].title, target: self, action: #selector(pasteButton(_:)))
        button.tag = index
        applyButtonTitle(config.buttons[index].title, to: button, identifier: identifier)
        button.isEnabled = config.pasteAuthorized
        item.view = button
        return item
    }
    private func applyButtonTitle(_ title: String, to button: NSButton, identifier: NSTouchBarItem.Identifier) {
        button.title = title
        button.font = .systemFont(ofSize: 13)
        button.cell?.lineBreakMode = .byTruncatingTail
        button.setAccessibilityLabel(title)
        let width = ButtonTitleLayout.width(for: title)
        if let constraint = titleWidths[identifier] { constraint.constant = width }
        else {
            let constraint = button.widthAnchor.constraint(equalToConstant: width)
            constraint.isActive = true
            titleWidths[identifier] = constraint
        }
    }
    private func buttonTitlesMatchConfiguration() -> Bool {
        guard let config else { return false }
        return itemIDs.enumerated().allSatisfy { index, identifier in
            let item = bar.item(forIdentifier: identifier) as? NSCustomTouchBarItem
            return (item?.view as? NSButton)?.title == config.buttons[index].title
        }
    }
    @objc private func pasteButton(_ sender: NSButton) {
        guard config.buttons.indices.contains(sender.tag) else { return }
        paste(text: config.buttons[sender.tag].text)
    }
    private func paste(text: String) {
        pasteOutcome = "Blocked by safety checks"
        focusNotice = "none"; proofStatus = "not checked"
        defer { updateDiagnostics() }
        // No prompting, permission requests, activation, scripts, or clipboard-content reads.
        guard config.pasteAuthorized, enabled, !sendGate.isPending, Date().timeIntervalSince(lastPaste) > 0.6,
              AXIsProcessTrusted(), CGPreflightPostEventAccess(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == config.targetBundleIdentifier else { NSSound.beep(); return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return }
        let field = focused as! AXUIElement
        var subrole: CFTypeRef?
        // Refuse password inputs without reading their contents.
        let subroleResult = AXUIElementCopyAttributeValue(field, kAXSubroleAttribute as CFString, &subrole)
        guard [.success, .noValue, .attributeUnsupported].contains(subroleResult),
              (subrole as? String) != kAXSecureTextFieldSubrole else { pasteOutcome = "Blocked: secure/unknown subrole"; return }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXRoleAttribute as CFString, &role) == .success,
              let roleName = role as? String,
              [kAXTextFieldRole, kAXTextAreaRole].contains(roleName),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { pasteOutcome = "Blocked: role/event/focus"; return }
        AXUIElementSetMessagingTimeout(field, 0.2)
        let initialRange = config.shouldAutoSend ? selectedRange(field) : nil
        let observedFocus = config.shouldAutoSend && startFocusObserver(pid: app.processIdentifier)
        if config.shouldAutoSend {
            proofStatus = initialRange == nil ? "AX selection range unavailable" : (observedFocus ? "waiting for echo" : "AX focus notification unavailable")
        }
        down.flags = .maskCommand; up.flags = .maskCommand
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        guard clipboard.setString(text, forType: .string) else { cancelAutoSend("Clipboard write failed"); return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { cancelAutoSend("Cancelled: application changed"); return }
        lastPaste = Date()
        if config.shouldAutoSend, observedFocus, let range = initialRange,
           sendGate.begin(pid: app.processIdentifier, text: text, insertionLocation: range.location,
                          now: ProcessInfo.processInfo.systemUptime, delay: config.sendDelay) {
            pendingField = field; pendingPID = app.processIdentifier; pendingText = text
            pendingInsertionLocation = range.location; pendingClipboardCount = clipboard.changeCount
        }
        down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
        if sendGate.isPending {
            pasteOutcome = "Pasted; waiting for verification"
            let polling = Timer(timeInterval: 0.05, target: self, selector: #selector(pollAutoSend), userInfo: nil, repeats: true)
            sendTimer = polling; RunLoop.main.add(polling, forMode: .common)
        } else {
            cancelAutoSend("No pending send")
            pasteOutcome = config.shouldAutoSend ? "Pasted; Return withheld (verification unavailable)" : "Command-V posted; no Return"
        }
    }

    private func selectedRange(_ field: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
              range.location >= 0, range.length >= 0 else { return nil }
        return range
    }
    private func safeFocusedField(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let field = value as! AXUIElement
        AXUIElementSetMessagingTimeout(field, 0.2)
        var role: CFTypeRef?, subrole: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(field, kAXSubroleAttribute as CFString, &subrole)
        guard [.success, .noValue, .attributeUnsupported].contains(result),
              (subrole as? String) != kAXSecureTextFieldSubrole,
              AXUIElementCopyAttributeValue(field, kAXRoleAttribute as CFString, &role) == .success,
              let roleName = role as? String, [kAXTextFieldRole, kAXTextAreaRole].contains(roleName) else { return nil }
        return field
    }
    private func startFocusObserver(pid: pid_t) -> Bool {
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            owner.handleFocusNotification()
        }, &observer) == .success, let observer else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard AXObserverAddNotification(observer, app, kAXFocusedUIElementChangedNotification as CFString,
                                        Unmanaged.passUnretained(self).toOpaque()) == .success else { return false }
        focusObserver = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        return true
    }
    private func handleFocusNotification() {
        guard sendGate.isPending, let pid = pendingPID, let original = pendingField else { return }
        let current = safeFocusedField(pid: pid)
        let same = current.map { CFEqual($0, original) } ?? false
        focusNotice = current == nil ? "focused field unavailable" : (same ? "same field notification ignored" : "different field confirmed")
        if sendGate.focusNotification(sameField: same) {
            cancelAutoSend("Cancelled: confirmed focus change or unavailable field")
        }
        updateDiagnostics()
    }
    private func recordRuntimeStatus() {
        // Only diagnostics about this tool: never text, clipboard contents, AX identifiers or ranges.
        let status: [String: Any] = [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "buttonTitlesMatchConfiguration": buttonTitlesMatchConfiguration(),
            "configurationReload": configurationOutcome, "configurationRevision": configurationRevision,
            "editMenuAvailable": self.status?.menu?.items.contains(where: { $0.title == "编辑配置" }) ?? false,
            "reloadMenuAvailable": self.status?.menu?.items.contains(where: { $0.title == "重新加载配置" }) ?? false,
            "outcome": pasteOutcome, "focusNotification": focusNotice, "pasteProof": proofStatus,
            "enabled": enabled, "pasteAuthorized": config?.pasteAuthorized ?? false,
            "autoSend": config?.shouldAutoSend ?? false,
            "AXTrusted": AXIsProcessTrusted(), "eventPosting": CGPreflightPostEventAccess(),
            "targetFrontmost": NSWorkspace.shared.frontmostApplication?.bundleIdentifier == config?.targetBundleIdentifier
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]),
              let encoded = String(data: data, encoding: .utf8), encoded != lastRecordedStatus else { return }
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("runtime-status.json")
        if (try? data.write(to: url, options: .atomic)) != nil { lastRecordedStatus = encoded }
    }
    private func cancelAutoSend(_ reason: String) {
        let active = sendGate.isPending || sendTimer != nil || diagnosticPasteWork != nil
        diagnosticPasteWork?.cancel(); diagnosticPasteWork = nil
        sendGate.cancel(); sendTimer?.invalidate(); sendTimer = nil
        if let observer = focusObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        focusObserver = nil; pendingField = nil; pendingPID = nil; pendingText = nil
        pendingInsertionLocation = nil; pendingClipboardCount = nil
        if active { pasteOutcome = reason }
    }
    private func sendObservation() -> SendObservation? {
        guard let field = pendingField, let pid = pendingPID, let text = pendingText,
              let location = pendingInsertionLocation else { return nil }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let targetMatches = frontmost?.bundleIdentifier == config.targetBundleIdentifier
        let current = targetMatches && frontmost?.processIdentifier == pid ? safeFocusedField(pid: pid) : nil
        let same = current.map { CFEqual($0, field) } ?? false
        let caret = same ? selectedRange(field) : nil
        var inserted: String?
        // Read only the bounded segment that was supposed to be inserted, never the entire input.
        if !same { proofStatus = "not checked: different/unavailable focused field" }
        else if caret == nil { proofStatus = "AX selection range unavailable after paste" }
        else if caret?.location != location + text.utf16.count || caret?.length != 0 { proofStatus = "caret/selection did not acknowledge paste" }
        if same, caret?.location == location + text.utf16.count, caret?.length == 0 {
            var requested = CFRange(location: location, length: text.utf16.count)
            if let parameter = AXValueCreate(.cfRange, &requested) {
                var value: CFTypeRef?
                let result = AXUIElementCopyParameterizedAttributeValue(field, kAXStringForRangeParameterizedAttribute as CFString,
                                                                        parameter, &value)
                if result == .success {
                    inserted = value as? String
                    proofStatus = inserted == text ? "inserted fragment matched" : "inserted fragment mismatch"
                } else { proofStatus = "AXStringForRange error \(result.rawValue)" }
            }
        }
        return SendObservation(frontmostPID: targetMatches ? frontmost?.processIdentifier : nil, sameField: same,
                               caretLocation: caret?.location, selectionLength: caret?.length, pastedText: inserted,
                               clipboardUnchanged: NSPasteboard.general.changeCount == pendingClipboardCount,
                               permissionsAvailable: AXIsProcessTrusted() && CGPreflightPostEventAccess(),
                               enabled: enabled && config.pasteAuthorized && config.shouldAutoSend)
    }
    @objc private func pollAutoSend() {
        defer { updateDiagnostics() }
        guard let observation = sendObservation() else { cancelAutoSend("Cancelled: no verification context"); return }
        switch sendGate.evaluate(observation, now: ProcessInfo.processInfo.systemUptime) {
        case .idle: cancelAutoSend("No pending send")
        case .waiting: break
        case .cancelled:
            let reason: String
            if observation.frontmostPID != pendingPID { reason = "frontmost application changed" }
            else if !observation.sameField { reason = "focused field changed/unavailable" }
            else if !observation.enabled { reason = "disabled" }
            else if !observation.permissionsAvailable { reason = "permission unavailable" }
            else if !observation.clipboardUnchanged { reason = "clipboard changed" }
            else { reason = "paste verification timed out: " + proofStatus }
            cancelAutoSend("Cancelled: " + reason)
        case .send:
            guard let final = sendObservation(), let pid = pendingPID,
                  let text = pendingText, let location = pendingInsertionLocation,
                  final.enabled, final.permissionsAvailable, final.frontmostPID == pid, final.sameField,
                  final.clipboardUnchanged, final.pastedText == text,
                  final.caretLocation == location + text.utf16.count, final.selectionLength == 0,
                  let down = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let field = pendingField, let current = safeFocusedField(pid: pid), CFEqual(current, field)
            else { cancelAutoSend("Cancelled: final verification failed"); return }
            down.flags = []; up.flags = []
            cancelAutoSend("Verification complete")
            down.postToPid(pid); up.postToPid(pid)
            pasteOutcome = "Verified paste; one Return posted"
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
