import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), name); checks += 1
}
let data = try Data(contentsOf: URL(fileURLWithPath: "config.example.json"))
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
check(!accepts { $0["buttons"] = Array(($0["buttons"] as! [[String: Any]]).reversed()) }, "reject reversed order")
check(!accepts { $0["buttons"] = Array(($0["buttons"] as! [[String: Any]]).dropLast()) }, "reject missing button")
check(!accepts { var b = $0["buttons"] as! [[String: Any]]; b.append(b[0]); $0["buttons"] = b }, "reject extra button")
check(!accepts { var b = $0["buttons"] as! [[String: Any]]; b[4]["id"] = "continue"; $0["buttons"] = b }, "reject duplicate ID")
check(!accepts { var b = $0["buttons"] as! [[String: Any]]; b[4]["id"] = "unknown"; $0["buttons"] = b }, "reject unknown ID")
check(!accepts { var b = $0["buttons"] as! [[String: Any]]; b[4]["title"] = "发送"; $0["buttons"] = b }, "reject changed label")
check(accepts { $0["pasteAuthorized"] = true }, "explicitly authorized runtime config")
check((try? JSONDecoder().decode(Configuration.self, from: Data("{broken}".utf8))) == nil, "reject malformed JSON")
print("PASS: \(checks) multi-button configuration checks")
