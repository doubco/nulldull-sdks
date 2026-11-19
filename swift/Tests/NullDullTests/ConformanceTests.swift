import Foundation
import Testing

@testable import NullDull

/// Runs every case in `fixtures/manifest.json` (SPEC.md section 11) against a mocked transport.
@Suite("Conformance manifest")
struct ConformanceTests {
    static let caseIDs = Fixtures.manifest.cases.map(\.id)

    @Test("manifest case", arguments: caseIDs)
    func manifestCase(_ id: String) async throws {
        let testCase = try #require(Fixtures.manifest.cases.first { $0.id == id })
        let replies = testCase.exchanges.map { exchange -> MockTransport.Reply in
            .response(status: exchange.response.status, headers: exchange.response.headers ?? [:], body: exchange.response.data)
        }
        let h = try harness(testCase.key, replies)
        let expect = testCase.expect

        var outcome: Outcome?
        var thrown: NullDullError?
        do {
            outcome = try await invoke(h.client, testCase.call.method, testCase.call.args)
        } catch let error as NullDullError {
            thrown = error
        }

        // Requests: method, path, query multimap and headers.
        let requests = h.transport.requests
        #expect(requests.count == (expect.attempts ?? testCase.exchanges.count), "attempts")
        for (index, request) in requests.enumerated() where index < testCase.exchanges.count {
            let expected = testCase.exchanges[index].request
            #expect(request.httpMethod == expected.method)
            #expect(percentEncodedPath(request) == expected.path)
            #expect(multimap(request) == expected.query)
            let key = testCase.key == "public" ? publicKey : privateKey
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "nulldull-sdk-swift/0.1.0")
            let accept = testCase.call.method.hasSuffix("downloadAsset") ? "*/*" : "application/json"
            #expect(request.value(forHTTPHeaderField: "Accept") == accept)
        }
        if let sleeps = expect.sleeps { #expect(h.sleeper.sleeps == sleeps, "sleeps") }

        if let errorExpectation = expect.error {
            let error = try #require(thrown, "expected an error")
            for (field, value) in errorExpectation {
                switch field {
                case "status": #expect(JSONValue.number(Double(error.status)) == value)
                case "code": #expect(JSONValue.string(error.code.rawValue) == value)
                case "message": #expect(JSONValue.string(error.message) == value)
                case "detail": #expect(error.detail.map(JSONValue.string) ?? .null == value)
                case "requestId": #expect(error.requestID.map(JSONValue.string) ?? .null == value)
                case "retryAfter": #expect(error.retryAfter.map { JSONValue.number(Double($0)) } ?? .null == value)
                case "body":
                    let body = try #require(error.body)
                    for (name, member) in value.objectValue ?? [:] { #expect(body[name] == member, "body.\(name)") }
                default: Issue.record("Unknown error field \(field)")
                }
            }
            return
        }
        if let thrown { Issue.record("Unexpected error: \(thrown.code) \(thrown.message)") }
        let result = try #require(outcome)

        if let download = expect.download {
            guard case .download(let value) = result else {
                Issue.record("Expected a download")
                return
            }
            #expect(value.contentType == download.contentType)
            #expect(value.filename == download.filename)
            #expect(value.size == download.size)
            #expect(value.bytes == Data(base64Encoded: download.bytesBase64))
            return
        }

        guard case .json(let json) = result else {
            Issue.record("Expected JSON")
            return
        }
        if let file = expect.resultFile {
            let except = expect.except ?? []
            #expect(json.removing(except) == Fixtures.json(file).removing(except))
        }
        if let count = expect.itemCount { #expect(json.arrayValue?.count == count) }
        for check in expect.checks ?? [] {
            #expect(json.at(check.path) == check.equals, "\(check.path)")
        }
    }
}

enum Outcome {
    case json(JSONValue)
    case download(Download)
}

/// Maps a canonical call such as `memory.listDocuments` with JSON arguments to the Swift API.
func invoke(_ client: NullDullClient, _ method: String, _ args: [JSONValue]) async throws -> Outcome {
    let options = args.last?.objectValue ?? [:]
    func string(_ index: Int) -> String { args[index].stringValue! }
    func opt(_ name: String) -> String? { options[name]?.stringValue }
    func int(_ name: String) -> Int? { options[name]?.intValue }
    func strings(_ name: String) -> [String]? { options[name]?.arrayValue?.compactMap(\.stringValue) }
    func folder(_ name: String) -> FolderFilter? {
        guard let value = options[name] else { return nil }  // omitted: no filter
        if let id = value.stringValue { return .id(id) }
        return .root  // null means the location root
    }
    func raw(_ model: some NullDullModel) -> Outcome { .json(model.raw) }
    func items<S: AsyncSequence>(_ sequence: S) async throws -> Outcome where S.Element: NullDullModel {
        .json(.array(try await collect(sequence).map(\.raw)))
    }

    let grid = client.grid
    let memory = client.memory
    switch method {
    case "grid.listPages":
        return raw(
            try await grid.listPages(
                string(0), locale: opt("locale") ?? "en", q: opt("q"), folderID: opt("folderId"), limit: int("limit"),
                after: opt("after")))
    case "grid.iteratePages":
        return try await items(
            grid.iteratePages(
                string(0), locale: opt("locale") ?? "en", q: opt("q"), folderID: opt("folderId"), limit: int("limit"),
                after: opt("after")))
    case "grid.getPage":
        return raw(try await grid.getPage(string(0), slug: string(1), locale: args.count > 2 ? opt("locale") ?? "en" : "en"))
    case "memory.listScopes":
        return raw(try await memory.listScopes(after: opt("after")))
    case "memory.iterateScopes":
        return try await items(memory.iterateScopes(after: opt("after")))
    case "memory.listFolders":
        return raw(try await memory.listFolders(scopeID: opt("scopeId"), parentID: folder("parentId"), after: opt("after")))
    case "memory.iterateFolders":
        return try await items(memory.iterateFolders(scopeID: opt("scopeId"), parentID: folder("parentId"), after: opt("after")))
    case "memory.getFolder":
        return raw(try await memory.getFolder(string(0)))
    case "memory.listDocuments":
        return raw(
            try await memory.listDocuments(
                scopeID: opt("scopeId"), folderID: folder("folderId"), tags: strings("tags") ?? [],
                kind: opt("kind").map(FileKind.init(rawValue:)), lifecycle: opt("lifecycle").map(FileLifecycle.init(rawValue:)),
                after: opt("after")))
    case "memory.iterateDocuments":
        return try await items(
            memory.iterateDocuments(
                scopeID: opt("scopeId"), folderID: folder("folderId"), tags: strings("tags") ?? [],
                kind: opt("kind").map(FileKind.init(rawValue:)), lifecycle: opt("lifecycle").map(FileLifecycle.init(rawValue:)),
                after: opt("after")))
    case "memory.getDocument":
        return raw(try await memory.getDocument(string(0)))
    case "memory.resolveLink":
        return raw(try await memory.resolveLink(string(0), href: string(1)))
    case "memory.search":
        let options = args.count > 1 ? options : [:]
        return raw(
            try await memory.search(
                string(0), scopeID: options["scopeId"]?.stringValue,
                tags: options["tags"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                kind: options["kind"]?.stringValue.map(FileKind.init(rawValue:)),
                lifecycle: options["lifecycle"]?.stringValue.map(FileLifecycle.init(rawValue:)),
                after: options["after"]?.stringValue))
    case "memory.iterateSearch":
        return try await items(memory.iterateSearch(string(0), scopeID: opt("scopeId"), tags: strings("tags") ?? []))
    case "memory.listTags":
        return raw(try await memory.listTags(scopeID: opt("scopeId"), q: opt("q"), after: opt("after")))
    case "memory.iterateTags":
        return try await items(memory.iterateTags(scopeID: opt("scopeId"), q: opt("q"), after: opt("after")))
    case "memory.listAssets":
        return raw(
            try await memory.listAssets(
                scopeID: opt("scopeId"), folderID: folder("folderId"), q: opt("q"), tags: strings("tags") ?? [],
                after: opt("after")))
    case "memory.iterateAssets":
        return try await items(
            memory.iterateAssets(
                scopeID: opt("scopeId"), folderID: folder("folderId"), q: opt("q"), tags: strings("tags") ?? [],
                after: opt("after")))
    case "memory.getAsset":
        return raw(try await memory.getAsset(string(0), revisionID: args.count > 1 ? opt("revisionId") : nil))
    case "memory.listAssetVersions":
        return raw(try await memory.listAssetVersions(string(0), after: args.count > 1 ? opt("after") : nil))
    case "memory.iterateAssetVersions":
        return try await items(memory.iterateAssetVersions(string(0), after: args.count > 1 ? opt("after") : nil))
    case "memory.downloadAsset":
        let options = args.count > 1 ? options : [:]
        return .download(
            try await memory.downloadAsset(
                string(0), revisionID: options["revisionId"]?.stringValue, preview: options["preview"]?.boolValue ?? false,
                width: options["width"]?.intValue))
    case "locale.listFormats":
        return raw(try await client.locale.listFormats())
    case "locale.export":
        let options = args.count > 1 ? options : [:]
        return raw(
            try await client.locale.export(
                scopeID: string(0),
                format: options["format"]?.stringValue.map(LocaleFormatID.init(rawValue:)) ?? .json,
                languages: options["languages"]?.arrayValue?.compactMap(\.stringValue),
                status: options["status"]?.arrayValue?.compactMap(\.stringValue).map(LocaleKeyStatus.init(rawValue:)),
                basename: options["basename"]?.stringValue))
    default:
        Issue.record("Unmapped method \(method)")
        throw NullDullError(status: 0, code: "UNMAPPED")
    }
}
