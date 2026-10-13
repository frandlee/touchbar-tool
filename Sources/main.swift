import AppKit
import ApplicationServices

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
    private var config: Configuration!
    private var shown = false
    private var enabled = true
    private var timer: Timer?
    private var lastPaste = Date.distantPast
    private var diagnosticWindow: NSWindow?
    private var diagnosticLabel: NSTextField?
    private var pasteOutcome = "Not attempted"

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let env = ProcessInfo.processInfo.environment["CODEX_TOUCHBAR_CONFIG"]
            let url = env.map { URL(fileURLWithPath: $0) }
                ?? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("config.json")
            config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
            try config.validate()
        } catch { fail("Configuration error: \(error.localizedDescription)"); return }
        guard CTBAvailable() else { fail("Private Touch Bar API unavailable; exiting safely."); return }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "CTB"
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "启用 Touch Bar", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggle.target = self; toggle.state = .on; menu.addItem(toggle)
        let info = NSMenuItem(title: config.pasteAuthorized ? "粘贴：需辅助功能权限" : "粘贴：待用户批准（关闭）", action: nil, keyEquivalent: "")
        menu.addItem(info)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Touchbar Tool", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); status.menu = menu
        bar.delegate = self
        bar.defaultItemIdentifiers = itemIDs
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(update),
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
        let field = NSTextField(frame: NSRect(x: 20, y: 82, width: 580, height: 30))
        field.placeholderString = "本应用测试输入框（不会发送）"
        field.setAccessibilityLabel("Prototype test input")
        window.contentView?.addSubview(field)
        let toggle = NSButton(title: "切换启用状态", target: self, action: #selector(diagnosticToggle))
        toggle.frame = NSRect(x: 20, y: 25, width: 150, height: 32)
        window.contentView?.addSubview(toggle)
        let paste = NSButton(title: "测试粘贴（仅本应用）", target: self, action: #selector(diagnosticPaste))
        paste.frame = NSRect(x: 180, y: 25, width: 230, height: 32)
        window.contentView?.addSubview(paste)
        let quit = NSButton(title: "退出", target: self, action: #selector(quitApp))
        quit.frame = NSRect(x: 440, y: 25, width: 150, height: 32)
        window.contentView?.addSubview(quit)
        diagnosticWindow = window
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeFirstResponder(field)
        updateDiagnostics()
    }
    private func updateDiagnostics() {
        diagnosticLabel?.stringValue = "AX trusted: \(AXIsProcessTrusted()); Event posting: \(CGPreflightPostEventAccess())\nEnabled: \(enabled); Paste authorized: \(config.pasteAuthorized)\nTarget: \(config.targetBundleIdentifier); Frontmost: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")\nButtons: \(config.buttons.map(\.title).joined(separator: "｜")); Presented: \(shown); Paste: \(pasteOutcome)"
    }
    @objc private func diagnosticToggle() { enabled.toggle(); update() }
    @objc private func diagnosticPaste() {
        // Diagnostic button cannot send to any other application.
        guard config.targetBundleIdentifier == Bundle.main.bundleIdentifier else { return }
        paste(text: config.buttons[0].text)
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
    @objc private func hideForSleep() { hide() }
    @objc private func toggleEnabled(_ item: NSMenuItem) {
        enabled.toggle(); item.state = enabled ? .on : .off; update()
    }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if shown { _ = CTBDismiss(bar) }
    }
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let index = itemIDs.firstIndex(of: identifier) else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        let button = NSButton(title: config.buttons[index].title, target: self, action: #selector(pasteButton(_:)))
        button.tag = index
        button.isEnabled = config.pasteAuthorized
        item.view = button
        return item
    }
    @objc private func pasteButton(_ sender: NSButton) {
        guard config.buttons.indices.contains(sender.tag) else { return }
        paste(text: config.buttons[sender.tag].text)
    }
    private func paste(text: String) {
        pasteOutcome = "Blocked by safety checks"
        defer { updateDiagnostics() }
        // No prompting, permission requests, activation, scripts, Return, or clipboard reads.
        guard config.pasteAuthorized, enabled, Date().timeIntervalSince(lastPaste) > 0.6,
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
        down.flags = .maskCommand; up.flags = .maskCommand
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        guard clipboard.setString(text, forType: .string) else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
        lastPaste = Date()
        down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
        pasteOutcome = "Command-V posted; no Return"
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
