import Foundation

enum ButtonIcon: Codable, Hashable, CaseIterable {
    case push, merge, deploy, pushMergeDeploy
    case custom(String)
    static let allCases: [ButtonIcon] = [.push, .merge, .deploy, .pushMergeDeploy]
    static let singleCases: [ButtonIcon] = [.push, .merge, .deploy]
    var rawValue: String {
        switch self {
        case .push: return "push"
        case .merge: return "merge"
        case .deploy: return "deploy"
        case .pushMergeDeploy: return "pushMergeDeploy"
        case .custom(let id): return "custom:" + id
        }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let known = Self.allCases.first(where: { $0.rawValue == value }) { self = known }
        else if value.hasPrefix("custom:"), let uuid = UUID(uuidString: String(value.dropFirst(7))) {
            self = .custom(uuid.uuidString)
        } else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown icon") }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    var label: String {
        switch self {
        case .custom: return "自定义图标"
        case .push: return "GitHub Push"
        case .merge: return "GitHub Merge"
        case .deploy: return "Deploy"
        case .pushMergeDeploy: return "Push · Merge · Deploy"
        }
    }
}

enum IconColor: String, Codable, CaseIterable {
    case automatic, blue, green, purple, orange, teal, red
    var label: String {
        switch self {
        case .automatic: return "原色/自动"
        case .blue: return "蓝色"
        case .green: return "绿色"
        case .purple: return "紫色"
        case .orange: return "橙色"
        case .teal: return "青色"
        case .red: return "红色"
        }
    }
}
struct IconSelection: Codable, Equatable {
    let icon: ButtonIcon
    let color: IconColor
}

struct ButtonConfiguration: Codable, Equatable {
    let id: String
    let title: String
    let text: String
    let icon: ButtonIcon?
    let icons: [IconSelection]?
    var effectiveIcons: [IconSelection] {
        if let icons { return icons }
        guard let icon else { return [] }
        let values: [ButtonIcon] = icon == .pushMergeDeploy ? [.push, .merge, .deploy] : [icon]
        return values.map { IconSelection(icon: $0, color: .automatic) }
    }
    init(id: String, title: String, text: String, icon: ButtonIcon? = nil, icons: [IconSelection]? = nil) {
        self.id = id; self.title = title; self.text = text; self.icon = icon; self.icons = icons
    }
}

struct Configuration: Codable, Equatable {
    static let maximumButtons = 20
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
        guard (1...Self.maximumButtons).contains(buttons.count),
              Set(buttons.map(\.id)).count == buttons.count,
              buttons.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 80 &&
                $0.id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-.")).contains($0) } })
        else { throw invalid("每个应用需有1～20个按钮，内部ID必须有效且不能重复。") }
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
            guard button.effectiveIcons.count <= 4,
                  !button.effectiveIcons.contains(where: { $0.icon == .pushMergeDeploy }) else {
                throw invalid("每个按钮最多组合4个独立图标。")
            }
            for selection in button.effectiveIcons {
                if case .custom(let id) = selection.icon, UUID(uuidString: id) == nil {
                    throw invalid("Invalid custom icon identifier.")
                }
            }

            if case .custom(let id) = button.icon, UUID(uuidString: id) == nil {
                throw invalid("Invalid custom icon identifier.")
            }
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


enum IconDropPayload {
    static func decode(_ data: Data?, currentCount: Int, available: [ButtonIcon]) -> ButtonIcon? {
        guard currentCount < 4, let data,
              let icon = try? JSONDecoder().decode(ButtonIcon.self, from: data),
              available.contains(icon) else { return nil }
        return icon
    }
}
