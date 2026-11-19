import Foundation

/// Locale catalog export (`locale:read`). Needs a private key and a workspace ID.
///
/// ```swift
/// let export = try await client.locale.export(scopeID: workspaceID, format: .xcstrings, basename: "Localizable")
/// try export.write(to: URL(fileURLWithPath: "Resources"))
/// ```
public struct LocaleAPI: Sendable {
    let requester: Requester
    let access: WorkspaceAccess

    /// Export formats with their capabilities and file roles.
    public func listFormats() async throws -> LocaleFormatList {
        try await requester.json(try access.root() + "/locale/formats", as: LocaleFormatList.self)
    }

    /// Exports a location's catalog as text files.
    ///
    /// Single-language formats give one file set per language (`en.json`, `values-tr/strings.xml`);
    /// `xcstrings` gives one file holding every language. Never an archive.
    ///
    /// - Parameters:
    ///   - scopeID: The location that holds the Locale library. The workspace root's ID equals the workspace ID.
    ///   - format: Default ``LocaleFormatID/json``; always sent.
    ///   - languages: Languages to export (comma-joined on the wire). `nil` or empty exports every configured language.
    ///   - status: Only keys with these statuses (comma-joined). `nil` or empty exports every status.
    ///   - basename: The base file name without extension, for example `Localizable`.
    public func export(
        scopeID: String,
        format: LocaleFormatID = .json,
        languages: [String]? = nil,
        status: [LocaleKeyStatus]? = nil,
        basename: String? = nil
    ) async throws -> LocaleExport {
        guard !scopeID.isEmpty else { throw NullDullError.invalidArgument("scopeID must be a non-empty string.") }
        let languages = try commaList(languages, "languages")
        let status = try commaList(status?.map(\.rawValue), "status")
        let root = try access.root()
        var query = Query()
        query.add("scopeId", scopeID)
        query.add("format", format.rawValue)
        query.add("languages", languages)
        query.add("status", status)
        query.add("basename", basename)
        return try await requester.json(root + "/locale/export", query, as: LocaleExport.self)
    }

    private func commaList(_ values: [String]?, _ name: String) throws -> String? {
        guard let values else { return nil }
        if values.contains(where: { $0.isEmpty || $0.contains(",") }) {
            throw NullDullError.invalidArgument("\(name) must be a list of non-empty strings without commas.")
        }
        return values.isEmpty ? nil : values.joined(separator: ",")
    }
}
