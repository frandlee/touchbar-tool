import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), name); checks += 1
}
let data = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/default-config.json"))
let configuration = try JSONDecoder().decode(Configuration.self, from: data)
try configuration.validate()
check(configuration.schemaVersion == 2, "schema version")
check(configuration.buttons.map(\.id) == ["continue", "check", "translate", "done", "merge"], "fixed order")
check(configuration.buttons.map(\.title) == ["继续", "查问题", "中日翻译", "DONE", "合并"], "fixed labels")
check(configuration.buttons.map(\.text) == ["继续", "检查当前问题，说明原因和建议的最小改动。", "请将下面内容做中日互译，表达自然、简短：", "DONE", "合并"], "exact requested texts")
check(!configuration.pasteAuthorized, "safe repository defaults")
let roundTrip = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(configuration))
try roundTrip.validate()
check(roundTrip.buttons.map(\.text) == configuration.buttons.map(\.text), "round trip")

func accepts(_ mutate: (inout [String: Any]) -> Void) -> Bool {
    var object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    mutate(&object)
    guard let encoded = try? JSONSerialization.data(withJSONObject: object),
          let config = try? JSONDecoder().decode(Configuration.self, from: encoded) else { return false }
    return (try? config.validate()) != nil
}
func editText(_ object: inout [String: Any], _ text: String) {
    var buttons = object["buttons"] as! [[String: Any]]
    buttons[1]["text"] = text; object["buttons"] = buttons
}
check(accepts { editText(&$0, "自定义短文字") }, "editable text")
check(accepts { editText(&$0, String(repeating: "字", count: 2000)) }, "text limit inclusive")
for bad in ["", "   ", "a\n", "a\r", "a\t", "a\u{0000}", "a\u{2028}", "a\u{2029}", String(repeating: "字", count: 2001)] {
    check(!accepts { editText(&$0, bad) }, "reject blank/control/newline/oversized text")
}
check(!accepts { $0["schemaVersion"] = 1 }, "reject old schema")
check(!accepts { $0.removeValue(forKey: "buttons") }, "reject missing buttons")
check(!accepts { $0["pasteAuthorized"] = "true" }, "reject malformed flag")
check(!accepts { $0["targetBundleIdentifier"] = "" }, "reject empty target")
check(!accepts { $0["targetBundleIdentifier"] = "com.example app" }, "reject target whitespace")
check(accepts { $0["buttons"] = Array(($0["buttons"] as! [[String: Any]]).reversed()) }, "custom order accepted")
check(accepts { $0["buttons"] = Array(($0["buttons"] as! [[String: Any]]).dropLast()) }, "fewer buttons accepted")
check(!accepts { var b = $0["buttons"] as! [[String: Any]]; b.append(b[0]); $0["buttons"] = b }, "reject extra button")
check(!accepts { var b = $0["buttons"] as! [[String: Any]]; b[4]["id"] = "continue"; $0["buttons"] = b }, "reject duplicate ID")
check(accepts { var b = $0["buttons"] as! [[String: Any]]; b[4]["id"] = "new-button"; $0["buttons"] = b }, "new internal ID accepted")
check(accepts { var b = $0["buttons"] as! [[String: Any]]; b[4]["title"] = "合并上线"; $0["buttons"] = b }, "custom title accepted")
check(accepts { $0["pasteAuthorized"] = true }, "explicitly authorized runtime config")
check((try? JSONDecoder().decode(Configuration.self, from: Data("{broken}".utf8))) == nil, "reject malformed JSON")
check(!accepts { $0["autoSend"] = "true" }, "reject malformed auto-send flag")
check(!accepts { $0["sendDelayMilliseconds"] = 199 }, "reject too-short delay")
check(!accepts { $0["sendDelayMilliseconds"] = 1501 }, "reject excessive delay")
check(accepts { $0.removeValue(forKey: "autoSend"); $0.removeValue(forKey: "sendDelayMilliseconds") }, "old schema 2 remains paste-only")
for title in ["", "   ", "x\n", "x\t", "x\u{2028}", String(repeating: "字", count: 21)] {
    check(!accepts { var b = $0["buttons"] as! [[String: Any]]; b[4]["title"] = title; $0["buttons"] = b }, "invalid custom title rejected")
}
check(accepts { var b = $0["buttons"] as! [[String: Any]]; b[4]["title"] = String(repeating: "字", count: 20); $0["buttons"] = b }, "title length boundary")
print("PASS: \(checks) multi-button configuration checks")

let second = Configuration(schemaVersion: 2, targetBundleIdentifier: "com.apple.TextEdit",
    buttons: configuration.buttons.map { ButtonConfiguration(id: $0.id, title: "测试", text: "本地测试") },
    pasteAuthorized: true, autoSend: false, sendDelayMilliseconds: 600)
let multi = Configuration.combining([configuration, second])
try multi.validate()
check(configuration.profiles.count == 1, "legacy file remains one profile")
check(multi.profiles.count == 2, "two independent profiles")
check(multi.profile(for: "com.apple.TextEdit") == second, "matches second application")
check(multi.profile(for: nil) == nil, "unknown bundle does not match")
check(multi.profile(for: "com.example.unconfigured") == nil, "unconfigured app hidden")
check(multi.profile(for: configuration.targetBundleIdentifier)?.buttons == configuration.buttons, "original texts retained")
check(second.pasteAuthorized && !second.shouldAutoSend, "new app paste only")
check(multi.profile(for: "com.apple.TextEdit")?.sendDelay == 0.6, "independent delay")
let decodedMulti = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(multi))
check(decodedMulti == multi, "multi application roundtrip")
check((try? Configuration.combining([configuration, configuration]).validate()) == nil, "duplicate applications rejected")
let nested = Configuration(schemaVersion: 2, targetBundleIdentifier: "com.example.nested", buttons: configuration.buttons,
    pasteAuthorized: true, autoSend: false, sendDelayMilliseconds: 400, applications: [second])
check((try? Configuration.combining([configuration, nested]).validate()) == nil, "nested profiles rejected")
print("PASS: 11 multi-application compatibility and matching checks")

check(accepts { $0["buttons"] = [($0["buttons"] as! [[String: Any]])[0]] }, "one button supported")
check(!accepts { $0["buttons"] = [] }, "empty application rejected")
check(accepts { $0["buttons"] = (0..<20).map { ["id": "button-\($0)", "title": "按钮", "text": "测试"] } }, "twenty button boundary")
check(!accepts { $0["buttons"] = (0..<21).map { ["id": "button-\($0)", "title": "按钮", "text": "测试"] } }, "oversized application rejected")
check(!accepts { var b = $0["buttons"] as! [[String: Any]]; b[0]["id"] = ""; $0["buttons"] = b }, "empty ID rejected")
let shortProfile = Configuration(schemaVersion: 2, targetBundleIdentifier: "com.example.short", buttons: Array(configuration.buttons.prefix(2)),
    pasteAuthorized: true, autoSend: false, sendDelayMilliseconds: 400)
let mixedCounts = Configuration.combining([configuration, shortProfile])
try mixedCounts.validate()
check(mixedCounts.profile(for: "com.example.short")?.buttons.count == 2, "each app has independent button count")
let persistedCounts = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(mixedCounts))
check(persistedCounts == mixedCounts, "different button counts survive roundtrip")
print("PASS: 7 variable button count checks")

check(configuration.buttons.allSatisfy { $0.icon == nil }, "legacy buttons remain text only")
for icon in ButtonIcon.allCases {
    let button = ButtonConfiguration(id: "icon-test", title: "Action", text: "unchanged command", icon: icon)
    let decoded = try JSONDecoder().decode(ButtonConfiguration.self, from: JSONEncoder().encode(button))
    check(decoded == button, "icon option roundtrip")
    check(decoded.text == "unchanged command", "icon does not change command")
}
check(!accepts { var b = $0["buttons"] as! [[String: Any]]; b[0]["icon"] = "invalid-icon"; $0["buttons"] = b }, "unknown icon rejected")
print("PASS: 10 icon configuration compatibility checks")
