import Foundation

/// What a Locale export format can represent.
public struct LocaleFormatCapabilities: NullDullModel {
    public let layout: LocaleLayout
    public let plurals: LocalePlurals
    public let variables: LocaleVariables
    public let status: Bool
    public let description: Bool
    public let variableTypes: Bool
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case layout, plurals, variables, status, description, variableTypes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = try c.req(.layout)
        plurals = try c.req(.plurals)
        variables = try c.req(.variables)
        status = try c.req(.status)
        description = try c.req(.description)
        variableTypes = try c.req(.variableTypes)
        raw = try JSONValue(from: decoder)
    }
}

/// A file role a format writes, such as `translations`.
public struct LocaleFormatFile: NullDullModel {
    public let role: String
    public let `extension`: String
    public let contentType: String
    public let required: Bool
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case role, `extension`, contentType, required }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.req(.role)
        `extension` = try c.req(.extension)
        contentType = try c.req(.contentType)
        required = try c.req(.required)
        raw = try JSONValue(from: decoder)
    }
}

/// A Locale export format.
public struct LocaleFormat: NullDullModel {
    public let id: LocaleFormatID
    public let label: String
    public let capabilities: LocaleFormatCapabilities
    public let files: [LocaleFormatFile]
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case id, label, capabilities, files }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        label = try c.req(.label)
        capabilities = try c.req(.capabilities)
        files = try c.req(.files)
        raw = try JSONValue(from: decoder)
    }
}

/// Every export format the API supports.
public struct LocaleFormatList: NullDullModel {
    public let items: [LocaleFormat]
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case items }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.req(.items)
        raw = try JSONValue(from: decoder)
    }
}

/// One exported text file.
public struct LocaleFile: NullDullModel {
    /// Relative path such as `en.json` or `values-tr/strings.xml`. May contain `/`.
    public let path: String
    public let contentType: String
    /// UTF-8 text.
    public let content: String
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case path, contentType, content }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.req(.path)
        contentType = try c.req(.contentType)
        content = try c.req(.content)
        raw = try JSONValue(from: decoder)
    }
}

/// Something the exporter had to leave out or change, for example `LOCALE_FORMAT_DESCRIPTION_OMITTED`.
public struct LocaleExportNote: NullDullModel {
    public let code: String
    public let key: String
    public let language: String?
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case code, key, language }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.req(.code)
        key = try c.req(.key)
        language = try c.opt(.language)
        raw = try JSONValue(from: decoder)
    }
}

/// A Locale export: always JSON holding text files, never an archive.
///
/// Single-language formats give one file set per language (`en.json`, `tr.json`);
/// `xcstrings` gives one file holding every language.
public struct LocaleExport: NullDullModel {
    public let format: LocaleFormatID
    public let files: [LocaleFile]
    public let notes: [LocaleExportNote]
    public let contentVersion: Int
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case format, files, notes, contentVersion }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.req(.format)
        files = try c.req(.files)
        notes = try c.opt(.notes) ?? []
        contentVersion = try c.req(.contentVersion)
        raw = try JSONValue(from: decoder)
    }

    /// Writes every file under `directory`, creating subdirectories as needed, and returns the
    /// written file URLs. Rejects absolute paths and `..` segments with `INVALID_ARGUMENT`
    /// before writing anything.
    @discardableResult
    public func write(to directory: URL) throws -> [URL] {
        let targets = try files.map { file -> (URL, LocaleFile) in
            let segments = file.path.split(separator: "/", omittingEmptySubsequences: false)
            if file.path.isEmpty || file.path.hasPrefix("/") || file.path.contains("\\")
                || segments.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
            {
                throw NullDullError.invalidArgument("Refusing to write the unsafe export path \"\(file.path)\".")
            }
            let url = segments.reduce(directory) { $0.appendingPathComponent(String($1)) }
            return (url, file)
        }
        let manager = FileManager.default
        for (url, file) in targets {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.content.utf8).write(to: url, options: .atomic)
        }
        return targets.map(\.0)
    }
}
