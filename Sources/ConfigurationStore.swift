import Foundation

final class ConfigurationStore {
    let url: URL
    private(set) var current: Configuration

    init(url: URL) throws {
        self.url = url
        current = try Self.read(url)
    }
    @discardableResult
    func reload(cancelPending: () -> Void) throws -> Configuration {
        // Cancel even when the replacement is invalid; never let an old send resume.
        cancelPending()
        let candidate = try Self.read(url)
        current = candidate // Commit only after read, decode and validation all succeed.
        return candidate
    }
    func save(_ candidate: Configuration, expected: Configuration, cancelPending: () -> Void) throws {
        cancelPending()
        try candidate.validate()
        // Refuse to recreate a missing runtime file or overwrite a directory.
        _ = try editingURL()
        guard try Self.read(url) == expected else {
            throw NSError(domain: "Configuration", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "配置文件已被其他操作修改。请关闭编辑窗口，重新加载配置后再编辑。"])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(candidate)
        try data.write(to: url, options: .atomic)
        current = candidate
    }
    func editingURL() throws -> URL {
        var directory: ObjCBool = false
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
              !directory.boolValue, FileManager.default.isReadableFile(atPath: url.path) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        }
        return url
    }
    private static func read(_ url: URL) throws -> Configuration {
        let candidate = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        try candidate.validate()
        return candidate
    }
    static func message(for error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, _): return "缺少必需字段：\(key.stringValue)。"
            case .typeMismatch, .valueNotFound: return "配置字段类型不正确，请对照默认配置。"
            case .dataCorrupted: return "JSON 格式不正确，请检查引号、逗号和括号。"
            @unknown default: return "无法解析配置，请对照默认配置。"
            }
        }
        let cocoa = error as NSError
        if cocoa.domain == "Configuration" { return "配置内容不符合要求：\(cocoa.localizedDescription)" }
        return "无法读取配置文件，请确认文件存在且可读取。"
    }
}
