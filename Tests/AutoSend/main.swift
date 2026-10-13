import AppKit
import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); checks += 1
}
let defaults = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/default-config.json")))
try defaults.validate()
check(!defaults.shouldAutoSend, "new repository default requires explicit auto-send configuration")
check(defaults.sendDelay == 0.4, "default delay")

func observation(text: String?, pid: Int32? = 7, same: Bool = true,
                 caret: Int? = nil, selection: Int? = 0,
                 clipboard: Bool = true, permission: Bool = true, enabled: Bool = true) -> SendObservation {
    SendObservation(frontmostPID: pid, sameField: same,
                    caretLocation: caret ?? text?.utf16.count, selectionLength: selection,
                    pastedText: text, clipboardUnchanged: clipboard,
                    permissionsAvailable: permission, enabled: enabled)
}

// Safe input simulation: offscreen Cocoa text controls; no CGEvent, AX calls,
// application activation, external UI, network requests, or real commands.
for button in defaults.buttons {
    let gate = AutoSendGate()
    let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
    check(gate.begin(pid: 7, text: button.text, insertionLocation: 0, now: 0, delay: 0.4), "begin for each button")
    field.insertText(button.text, replacementRange: NSRange(location: 0, length: 0))
    check(field.string == button.text, "local simulated paste matches configured text")
    let correct = observation(text: field.string, caret: field.selectedRange().location)
    check(gate.evaluate(correct, now: 0.05) == .waiting, "no immediate Return")
    check(gate.evaluate(correct, now: 0.39) == .waiting, "minimum delay enforced")
    check(gate.evaluate(correct, now: 0.4) == .send, "verified insertion permits one Return")
    field.insertNewline(nil)
    check(field.string == button.text + "\n", "one local simulated Return only")
    check(gate.evaluate(correct, now: 0.45) == .idle, "no duplicate Return")
    check(!gate.begin(pid: 7, text: button.text, insertionLocation: 0, now: 0.5, delay: 0.4), "cooldown blocks retrigger")
}
let text = "安全测试🙂"
func pendingGate() -> AutoSendGate {
    let gate = AutoSendGate()
    check(gate.begin(pid: 7, text: text, insertionLocation: 0, now: 10, delay: 0.4), "begin simulated session")
    check(!gate.begin(pid: 7, text: text, insertionLocation: 0, now: 11, delay: 0.4), "busy blocks second paste")
    return gate
}
for blocked in [
    observation(text: text, pid: 8), observation(text: text, pid: nil),
    observation(text: text, same: false), observation(text: text, clipboard: false),
    observation(text: text, permission: false), observation(text: text, enabled: false)
] {
    let gate = pendingGate()
    check(gate.evaluate(blocked, now: 10.5) == .cancelled, "unsafe context cancels")
    check(gate.evaluate(observation(text: text), now: 10.6) == .idle, "restored context cannot revive cancelled send")
}
for unverified in [observation(text: nil), observation(text: "错误内容"),
                   observation(text: text, caret: 1), observation(text: text, selection: 1)] {
    let gate = pendingGate()
    check(gate.evaluate(unverified, now: 10.5) == .waiting, "missing/wrong paste proof never sends")
    check(gate.evaluate(unverified, now: 12) == .cancelled, "unverified paste times out")
}
let gate = pendingGate()
gate.cancel() // Models application/focus change notification during the delay.
check(gate.evaluate(observation(text: text), now: 10.5) == .idle, "focus switch and restoration remains cancelled")
let selectionGate = AutoSendGate()
check(selectionGate.begin(pid: 7, text: text, insertionLocation: 3, now: 20, delay: 0.4), "nonzero/replaced selection")
let selected = observation(text: text, caret: 3 + text.utf16.count)
check(selectionGate.evaluate(selected, now: 20.3) == .waiting, "UTF-16 caret proof before delay")
check(selectionGate.evaluate(selected, now: 20.5) == .send, "UTF-16 caret proof after delay")
let duplicateGate = AutoSendGate()
check(duplicateGate.begin(pid: 7, text: text, insertionLocation: 0, now: 30, delay: 0.4), "duplicate-focus regression begin")
check(!duplicateGate.focusNotification(sameField: true), "same field focus notification does not cancel")
check(duplicateGate.isPending, "duplicate notification retains pending send")
check(duplicateGate.evaluate(observation(text: text), now: 30.3) == .waiting, "duplicate-focus proof before delay")
check(duplicateGate.evaluate(observation(text: text), now: 30.5) == .send, "duplicate-focus still sends once after verification")
let changedGate = AutoSendGate()
check(changedGate.begin(pid: 7, text: text, insertionLocation: 0, now: 40, delay: 0.4), "real-focus regression begin")
check(changedGate.focusNotification(sameField: false), "different input cancels immediately")
check(changedGate.evaluate(observation(text: text), now: 40.5) == .idle, "restoring focus cannot revive send")
let overflowGate = AutoSendGate()
check(!overflowGate.begin(pid: 7, text: text, insertionLocation: Int.max, now: 50, delay: 0.4), "invalid AX range cannot overflow")
print("PASS: \(checks) auto-send safety and offscreen input simulation checks; no external input events")
