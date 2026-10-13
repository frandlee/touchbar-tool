import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message); checks += 1
}
let data = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/default-config.json"))
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("touchbar-reload-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: directory) }
let url = directory.appendingPathComponent("config.json")
try data.write(to: url)
let store = try ConfigurationStore(url: url)
let initial = store.current
check(store.url == url, "uses exact runtime source URL")
let initialEditingURL = try store.editingURL()
check(initialEditingURL == url, "editor opens exact running configuration")
var candidate = try JSONSerialization.jsonObject(with: data) as! [String: Any]
candidate["pasteAuthorized"] = true; candidate["autoSend"] = true; candidate["sendDelayMilliseconds"] = 700
var buttons = candidate["buttons"] as! [[String: Any]]
buttons[0]["text"] = "安全重载测试"
buttons[4]["title"] = "合并上线"
candidate["buttons"] = buttons
let valid = try JSONSerialization.data(withJSONObject: candidate)
try valid.write(to: url)
let gate = AutoSendGate()
check(gate.begin(pid: 7, text: "旧任务", insertionLocation: 0, now: 0, delay: 0.4), "old send queued")
var cancellations = 0
let replacement = try store.reload { cancellations += 1; gate.cancel() }
check(cancellations == 1, "reload cancels before committing")
check(replacement == store.current, "returned/current replacement identical")
check(store.current.buttons[0].text == "安全重载测试", "new button behavior")
check(store.current.buttons[4].title == "合并上线", "custom title reloads")
check(store.current.buttons[4].text == initial.buttons[4].text, "title reload does not alter send text")
check(store.current.shouldAutoSend && store.current.pasteAuthorized && store.current.sendDelay == 0.7, "updated flags/delay")
let oldProof = SendObservation(frontmostPID: 7, sameField: true, caretLocation: 3, selectionLength: 0,
                               pastedText: "旧任务", clipboardUnchanged: true, permissionsAvailable: true, enabled: true)
check(gate.evaluate(oldProof, now: 0.5) == .idle, "old send cannot return after reload")
let retained = store.current
func reject(_ malformed: Data) throws {
    try malformed.write(to: url)
    check(gate.begin(pid: 7, text: "旧任务", insertionLocation: 0, now: Double(cancellations + 10), delay: 0.4), "queue before failed reload")
    do {
        _ = try store.reload { cancellations += 1; gate.cancel() }
        fatalError("Invalid configuration accepted")
    } catch {
        check(!ConfigurationStore.message(for: error).isEmpty, "understandable error")
        check(store.current == retained, "all old fields retained atomically")
        check(!gate.isPending, "failed reload also cancels pending send")
    }
}
try reject(Data("{broken}".utf8))
var invalid = candidate; invalid["buttons"] = []
try reject(JSONSerialization.data(withJSONObject: invalid))
invalid = candidate; invalid["autoSend"] = "true"
try reject(JSONSerialization.data(withJSONObject: invalid))
invalid = candidate; invalid["sendDelayMilliseconds"] = 1
try reject(JSONSerialization.data(withJSONObject: invalid))
try FileManager.default.removeItem(at: url)
do { _ = try store.reload { cancellations += 1; gate.cancel() }; fatalError("Missing file accepted") }
catch { check(store.current == retained, "missing file retains configuration") }
do { _ = try store.editingURL(); fatalError("Missing edit file accepted") }
catch { check(!ConfigurationStore.message(for: error).isEmpty, "missing editor file yields understandable error") }
try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
do { _ = try store.editingURL(); fatalError("Directory accepted as edit file") }
catch { check(true, "directory rejected by editor") }
try FileManager.default.removeItem(at: url)
try data.write(to: url)
_ = try store.reload { cancellations += 1; gate.cancel() }
check(store.current == initial, "recovery after invalid configuration")
let restoredEditingURL = try store.editingURL()
check(restoredEditingURL == url, "editor works after file restored")
print("PASS: \(checks) configuration reload/edit safety checks; no external input or editor launch")

let draft = Configuration(schemaVersion: initial.schemaVersion, targetBundleIdentifier: initial.targetBundleIdentifier,
    buttons: replacement.buttons, pasteAuthorized: true, autoSend: false, sendDelayMilliseconds: 500)
try store.save(draft, expected: initial) { cancellations += 1 }
let saved = try ConfigurationStore(url: url)
check(saved.current == draft && store.current == draft, "table save persists all fields")
let savedBytes = try Data(contentsOf: url)
do {
    try store.save(initial, expected: initial) { cancellations += 1 }
    fatalError("Stale draft overwrote newer configuration")
} catch {
    check((try? Data(contentsOf: url)) == savedBytes, "stale table draft preserves disk")
    check(store.current == draft, "stale draft preserves live config")
}
let invalidDraft = Configuration(schemaVersion: 2, targetBundleIdentifier: initial.targetBundleIdentifier,
    buttons: [], pasteAuthorized: true, autoSend: true, sendDelayMilliseconds: 400)
do {
    try store.save(invalidDraft, expected: draft) { cancellations += 1 }
    fatalError("Invalid draft saved")
} catch {
    check((try? Data(contentsOf: url)) == savedBytes, "invalid table draft preserves disk")
    check(store.current == draft, "invalid draft preserves live config")
}
print("PASS: table save and stale draft protection")

let another = Configuration(schemaVersion: 2, targetBundleIdentifier: "com.apple.TextEdit", buttons: initial.buttons,
    pasteAuthorized: true, autoSend: false, sendDelayMilliseconds: 400)
let multiple = Configuration.combining([draft, another])
try store.save(multiple, expected: draft) { cancellations += 1 }
let multipleRead = try ConfigurationStore(url: url)
check(multipleRead.current == multiple, "multi profile save retains every application")
check(multipleRead.current.profile(for: "com.apple.TextEdit")?.shouldAutoSend == false, "saved new app does not auto send")
print("PASS: 2 multi-application persistence checks")

let reduced = Configuration(schemaVersion: 2, targetBundleIdentifier: another.targetBundleIdentifier,
    buttons: Array(another.buttons.prefix(1)), pasteAuthorized: true, autoSend: false, sendDelayMilliseconds: 400)
let resized = Configuration.combining([draft, reduced])
try store.save(resized, expected: multiple) { cancellations += 1 }
let resizedRead = try ConfigurationStore(url: url)
check(resizedRead.current.profiles.map { $0.buttons.count } == [5, 1], "independent resized counts persisted")
print("PASS: variable button count save")

var iconButtons = reduced.buttons
iconButtons[0] = ButtonConfiguration(id: iconButtons[0].id, title: iconButtons[0].title,
    text: iconButtons[0].text, icon: .pushMergeDeploy)
let iconProfile = Configuration(schemaVersion: 2, targetBundleIdentifier: reduced.targetBundleIdentifier,
    buttons: iconButtons, pasteAuthorized: reduced.pasteAuthorized, autoSend: reduced.autoSend, sendDelayMilliseconds: 400)
let iconDocument = Configuration.combining([draft, iconProfile])
try store.save(iconDocument, expected: resized) { cancellations += 1 }
let iconsRead = try ConfigurationStore(url: url)
check(iconsRead.current.profiles[1].buttons[0].icon == .pushMergeDeploy, "icon saved per app/button")
check(iconsRead.current.profiles[1].buttons[0].text == reduced.buttons[0].text, "icon save preserves send text")
print("PASS: 2 icon persistence checks")
