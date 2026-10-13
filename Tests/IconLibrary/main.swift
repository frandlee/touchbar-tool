import AppKit
let app = NSApplication.shared
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("touchbar-icons-test-" + UUID().uuidString)
IconLibrary.directory = directory
 defer { try? FileManager.default.removeItem(at: directory) }
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message); checks += 1 }
check(IconLibrary.icons.isEmpty, "missing library is empty")
try IconLibrary.importImage(URL(fileURLWithPath: "Assets/Octicons/repo-push.png"))
check(IconLibrary.icons.count == 1, "import enters global library")
let icon = IconLibrary.icons[0]
check(IconLibrary.label(for: icon) == "repo-push", "import preserves source display name")
check(ButtonIconImage.image(for: icon) != nil, "imported asset renders")
let roundTrip = try JSONDecoder().decode(ButtonIcon.self, from: JSONEncoder().encode(icon))
check(roundTrip == icon, "custom UUID roundtrip")
check((try? JSONDecoder().decode(ButtonIcon.self, from: Data("\"custom:../../secret\"".utf8))) == nil, "path traversal rejected")
check(ButtonIconImage.image(for: .custom("../secret")) == nil, "invalid direct ID never reads external file")
if case .custom(let id) = icon {
    let png = directory.appendingPathComponent(id + ".png")
    let rep = NSBitmapImageRep(data: try Data(contentsOf: png))!
    check(rep.pixelsWide == 128 && rep.pixelsHigh == 128, "import normalized to bounded PNG")
    try "Renamed icon".write(to: directory.appendingPathComponent(id + ".name"), atomically: true, encoding: .utf8)
    check(IconLibrary.label(for: icon) == "Renamed icon", "renaming does not alter reference")
    try FileManager.default.removeItem(at: png)
    check(ButtonIconImage.image(for: icon) == nil, "missing custom asset falls back to title")
}
print("PASS: \(checks) local icon library checks; no user configuration or external input")
