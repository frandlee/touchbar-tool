import Foundation

struct ButtonConfiguration: Codable, Equatable {
    let id: String
    let title: String
    let text: String
}

struct Configuration: Codable, Equatable {
    static let fixedIDs = ["continue", "check", "translate", "done", "merge"]
    let schemaVersion: Int
    let targetBundleIdentifier: String
    let buttons: [ButtonConfiguration]
    let pasteAuthorized: Bool
    let autoSend: Bool?
    let sendDelayMilliseconds: Int?
    let applications: [Configuration]?

    init(schemaVersion: Int, targetBundleIdentifier: String, buttons: [ButtonConfiguration],
         pasteAuthorized: Bool, autoSend: Bool?, sendDelayMilliseconds: Int?, applications: [Configuration]? = nil) {
        self.schemaVersion = schemaVersion
        self.targetBundleIdentifier = targetBundleIdentifier
        self.buttons = buttons
        self.pasteAuthorized = pasteAuthorized
        self.autoSend = autoSend
        self.sendDelayMilliseconds = sendDelayMilliseconds
        self.applications = applications
    }
    var profiles: [Configuration] {
        [Configuration(schemaVersion: schemaVersion, targetBundleIdentifier: targetBundleIdentifier,
            buttons: buttons, pasteAuthorized: pasteAuthorized, autoSend: autoSend,
            sendDelayMilliseconds: sendDelayMilliseconds)] + (applications ?? [])
    }
    func profile(for bundleIdentifier: String?) -> Configuration? {
        profiles.first { $0.targetBundleIdentifier == bundleIdentifier }
    }
    static func combining(_ profiles: [Configuration]) -> Configuration {
        precondition(!profiles.isEmpty)
        let first = profiles[0]
        return Configuration(schemaVersion: first.schemaVersion, targetBundleIdentifier: first.targetBundleIdentifier,
            buttons: first.buttons, pasteAuthorized: first.pasteAuthorized, autoSend: first.autoSend,
            sendDelayMilliseconds: first.sendDelayMilliseconds,
            applications: profiles.count > 1 ? Array(profiles.dropFirst()) : nil)
    }
    var shouldAutoSend: Bool { autoSend ?? false }
    var sendDelay: TimeInterval { Double(sendDelayMilliseconds ?? 400) / 1000 }

    func validate() throws {
        func invalid(_ message: String) -> NSError {
            NSError(domain: "Configuration", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard schemaVersion == 2 else { throw invalid("Unsupported schemaVersion; use version 2 configuration.") }
        guard !targetBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !targetBundleIdentifier.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
        else { throw invalid("Target bundle identifier must not be empty or contain whitespace.") }
        guard buttons.map(\.id) == Self.fixedIDs
        else { throw invalid("必须恰好五个按钮，ID顺序固定为 continue、check、translate、done、merge。") }
        guard (200...1500).contains(sendDelayMilliseconds ?? 400) else { throw invalid("Send delay must be 200...1500 milliseconds.") }
        if let applications {
            var identifiers: Set<String> = [targetBundleIdentifier]
            for application in applications {
                guard application.applications == nil,
                      identifiers.insert(application.targetBundleIdentifier).inserted else {
                    throw invalid("应用不能重复，且不能包含嵌套应用配置。")
                }
                try application.validate()
            }
        }
        let forbidden = CharacterSet.controlCharacters.union(.newlines)
        for button in buttons {
            guard !button.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  button.title.count <= 20,
                  !button.title.unicodeScalars.contains(where: { forbidden.contains($0) })
            else { throw invalid("按钮 \(button.id) 的标题需为1～20个字符，不能只有空白、包含换行或控制字符。") }
            guard !button.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  button.text.count <= 2000,
                  !button.text.unicodeScalars.contains(where: { forbidden.contains($0) })
            else { throw invalid("Invalid text for \(button.id): blank, longer than 2000 characters, or contains control/newline characters.") }
        }
    }
}
