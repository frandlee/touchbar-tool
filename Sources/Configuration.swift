import Foundation

struct ButtonConfiguration: Codable {
    let id: String
    let title: String
    let text: String
}

struct Configuration: Codable {
    static let fixedIDs = ["continue", "check", "translate", "done", "merge"]
    static let fixedTitles = ["继续", "查问题", "中日翻译", "DONE", "合并"]
    let schemaVersion: Int
    let targetBundleIdentifier: String
    let buttons: [ButtonConfiguration]
    let pasteAuthorized: Bool

    func validate() throws {
        func invalid(_ message: String) -> NSError {
            NSError(domain: "Configuration", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard schemaVersion == 2 else { throw invalid("Unsupported schemaVersion; use version 2 configuration.") }
        guard !targetBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !targetBundleIdentifier.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
        else { throw invalid("Target bundle identifier must not be empty or contain whitespace.") }
        guard buttons.map(\.id) == Self.fixedIDs, buttons.map(\.title) == Self.fixedTitles
        else { throw invalid("Expected exactly five buttons in order: 继续｜查问题｜中日翻译｜DONE｜合并. IDs and titles are fixed.") }
        let forbidden = CharacterSet.controlCharacters.union(.newlines)
        for button in buttons {
            guard !button.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  button.text.count <= 2000,
                  !button.text.unicodeScalars.contains(where: { forbidden.contains($0) })
            else { throw invalid("Invalid text for \(button.id): blank, longer than 2000 characters, or contains control/newline characters.") }
        }
    }
}
