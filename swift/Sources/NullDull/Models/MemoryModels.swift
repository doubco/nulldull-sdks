import Foundation

/// A Memory location: the workspace root, a customer product or a project.
public struct Scope: NullDullModel {
    public let id: String
    public let name: String
    public let kind: LocationKind
    public let parentID: String?
    public let iconKind: IconKind?
    public let iconValue: String?
    public let iconVersion: Int?
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, iconKind, iconValue, iconVersion
        case parentID = "parentId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        name = try c.req(.name)
        kind = try c.req(.kind)
        parentID = try c.opt(.parentID)
        iconKind = try c.opt(.iconKind)
        iconValue = try c.opt(.iconValue)
        iconVersion = try c.opt(.iconVersion)
        raw = try JSONValue(from: decoder)
    }
}

/// One level of a location path, root first.
public typealias LocationPathItem = Scope

/// Where a file or folder is checked out in a repository.
public struct Placement: NullDullModel {
    public let repository: String?
    public let path: String
    /// Folder names joined with `/`; `""` at the location root.
    public let folderPath: String
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case repository, path, folderPath }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repository = try c.opt(.repository)
        path = try c.req(.path)
        folderPath = try c.req(.folderPath)
        raw = try JSONValue(from: decoder)
    }
}

/// A folder's ID and name, as in ``Folder/ancestors`` and ``Asset/folderPath``.
public struct FolderReference: NullDullModel {
    public let id: String
    public let name: String
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case id, name }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        name = try c.req(.name)
        raw = try JSONValue(from: decoder)
    }
}

/// A folder with its item counts, as listed by ``MemoryAPI/listFolders(scopeID:parentID:after:)``.
public struct FolderSummary: NullDullModel {
    public let workspaceID: String
    public let id: String
    public let scopeID: String
    public let parentID: String?
    public let name: String
    public let createdBy: String
    public let preferredRepository: String?
    public let preferredPath: String?
    public let metadataVersion: Int
    public let folderCount: Int
    public let documentCount: Int
    public let assetCount: Int
    public let secretCount: Int
    public let placement: Placement
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case name, createdBy, preferredRepository, preferredPath, metadataVersion
        case folderCount, documentCount, assetCount, secretCount, placement, id
        case workspaceID = "workspaceId", scopeID = "scopeId", parentID = "parentId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try c.req(.workspaceID)
        id = try c.req(.id)
        scopeID = try c.req(.scopeID)
        parentID = try c.opt(.parentID)
        name = try c.req(.name)
        createdBy = try c.req(.createdBy)
        preferredRepository = try c.opt(.preferredRepository)
        preferredPath = try c.opt(.preferredPath)
        metadataVersion = try c.req(.metadataVersion)
        folderCount = try c.req(.folderCount)
        documentCount = try c.req(.documentCount)
        assetCount = try c.req(.assetCount)
        secretCount = try c.req(.secretCount)
        placement = try c.req(.placement)
        raw = try JSONValue(from: decoder)
    }
}

/// Item counts directly inside the listed parent (``FolderList/here``).
public struct FolderCounts: NullDullModel {
    public let folders: Int
    public let documents: Int
    public let assets: Int
    public let secrets: Int
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case folders, documents, assets, secrets }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folders = try c.req(.folders)
        documents = try c.req(.documents)
        assets = try c.req(.assets)
        secrets = try c.req(.secrets)
        raw = try JSONValue(from: decoder)
    }
}

/// One page of folders.
public struct FolderList: NullDullModel {
    public let items: [FolderSummary]
    public let nextCursor: String?
    /// Only on the first page when both `scopeID` and `parentID` were given.
    public let here: FolderCounts?
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case items, nextCursor, here }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.req(.items)
        nextCursor = try c.opt(.nextCursor)
        here = try c.opt(.here)
        raw = try JSONValue(from: decoder)
    }
}

/// A folder with its ancestors and effective placement.
public struct Folder: NullDullModel {
    public let workspaceID: String
    public let id: String
    public let scopeID: String
    public let parentID: String?
    public let name: String
    public let createdBy: String
    public let preferredRepository: String?
    public let preferredPath: String?
    public let metadataVersion: Int
    public let canManage: Bool
    public let canDelete: Bool
    public let placement: Placement
    /// Root first.
    public let ancestors: [FolderReference]
    public let contents: FolderContents
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, name, createdBy, preferredRepository, preferredPath, metadataVersion
        case canManage, canDelete, placement, ancestors, contents
        case workspaceID = "workspaceId", scopeID = "scopeId", parentID = "parentId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try c.req(.workspaceID)
        id = try c.req(.id)
        scopeID = try c.req(.scopeID)
        parentID = try c.opt(.parentID)
        name = try c.req(.name)
        createdBy = try c.req(.createdBy)
        preferredRepository = try c.opt(.preferredRepository)
        preferredPath = try c.opt(.preferredPath)
        metadataVersion = try c.req(.metadataVersion)
        canManage = try c.req(.canManage)
        canDelete = try c.req(.canDelete)
        placement = try c.req(.placement)
        ancestors = try c.req(.ancestors)
        contents = try c.req(.contents)
        raw = try JSONValue(from: decoder)
    }
}

/// A Markdown document without its content.
public struct DocumentSummary: NullDullModel {
    public let id: String
    public let name: String
    public let scopeID: String
    public let folderID: String?
    public let headRevisionID: String?
    public let preferredRepository: String?
    public let preferredPath: String?
    public let metadataVersion: Int
    public let role: FileRole
    public let tags: [String]
    public let labelKind: FileKind?
    public let labelLifecycle: FileLifecycle?
    public let labelSource: LabelSource?
    public let labelStatus: LabelStatus
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, name, preferredRepository, preferredPath, metadataVersion, role
        case tags, labelKind, labelLifecycle, labelSource, labelStatus
        case scopeID = "scopeId", folderID = "folderId", headRevisionID = "headRevisionId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        name = try c.req(.name)
        scopeID = try c.req(.scopeID)
        folderID = try c.opt(.folderID)
        headRevisionID = try c.opt(.headRevisionID)
        preferredRepository = try c.opt(.preferredRepository)
        preferredPath = try c.opt(.preferredPath)
        metadataVersion = try c.req(.metadataVersion)
        role = try c.req(.role)
        tags = try c.req(.tags)
        labelKind = try c.opt(.labelKind)
        labelLifecycle = try c.opt(.labelLifecycle)
        labelSource = try c.opt(.labelSource)
        labelStatus = try c.req(.labelStatus)
        raw = try JSONValue(from: decoder)
    }
}

/// A Markdown document with its saved content.
public struct Document: NullDullModel {
    public let id: String
    public let name: String
    public let scopeID: String
    public let folderID: String?
    public let headRevisionID: String?
    public let headAuthorMemberID: String?
    public let preferredRepository: String?
    public let preferredPath: String?
    public let metadataVersion: Int
    public let role: FileRole
    public let tags: [String]
    public let labelKind: FileKind?
    public let labelLifecycle: FileLifecycle?
    public let labelSource: LabelSource?
    public let labelStatus: LabelStatus
    /// Saved Markdown (up to 128 KiB), or `nil` before the first save.
    public let content: String?
    public let contentHash: String?
    public let placement: Placement
    /// Root first, up to three levels.
    public let locationPath: [LocationPathItem]
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, name, preferredRepository, preferredPath, metadataVersion, role
        case tags, labelKind, labelLifecycle, labelSource, labelStatus
        case content, contentHash, placement, locationPath
        case scopeID = "scopeId", folderID = "folderId", headRevisionID = "headRevisionId"
        case headAuthorMemberID = "headAuthorMemberId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        name = try c.req(.name)
        scopeID = try c.req(.scopeID)
        folderID = try c.opt(.folderID)
        headRevisionID = try c.opt(.headRevisionID)
        headAuthorMemberID = try c.opt(.headAuthorMemberID)
        preferredRepository = try c.opt(.preferredRepository)
        preferredPath = try c.opt(.preferredPath)
        metadataVersion = try c.req(.metadataVersion)
        role = try c.req(.role)
        tags = try c.req(.tags)
        labelKind = try c.opt(.labelKind)
        labelLifecycle = try c.opt(.labelLifecycle)
        labelSource = try c.opt(.labelSource)
        labelStatus = try c.req(.labelStatus)
        content = try c.opt(.content)
        contentHash = try c.opt(.contentHash)
        placement = try c.req(.placement)
        locationPath = try c.req(.locationPath)
        raw = try JSONValue(from: decoder)
    }
}

/// A search hit with an excerpt around the match.
public struct SearchResult: NullDullModel {
    public let id: String
    public let name: String
    public let scopeID: String
    public let folderID: String?
    public let headRevisionID: String?
    public let metadataVersion: Int
    public let role: FileRole
    public let tags: [String]
    public let labelKind: FileKind?
    public let labelLifecycle: FileLifecycle?
    public let labelSource: LabelSource?
    public let labelStatus: LabelStatus
    /// Up to 240 characters around the match.
    public let excerpt: String
    public let locationPath: [LocationPathItem]
    public let folderPath: String
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, name, metadataVersion, role, tags, labelKind, labelLifecycle, labelSource, labelStatus
        case excerpt, locationPath, folderPath
        case scopeID = "scopeId", folderID = "folderId", headRevisionID = "headRevisionId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        name = try c.req(.name)
        scopeID = try c.req(.scopeID)
        folderID = try c.opt(.folderID)
        headRevisionID = try c.opt(.headRevisionID)
        metadataVersion = try c.req(.metadataVersion)
        role = try c.req(.role)
        tags = try c.req(.tags)
        labelKind = try c.opt(.labelKind)
        labelLifecycle = try c.opt(.labelLifecycle)
        labelSource = try c.opt(.labelSource)
        labelStatus = try c.req(.labelStatus)
        excerpt = try c.req(.excerpt)
        locationPath = try c.req(.locationPath)
        folderPath = try c.req(.folderPath)
        raw = try JSONValue(from: decoder)
    }
}

/// A tag with the number of readable documents that carry it.
public struct TagCount: NullDullModel {
    public let tag: String
    public let count: Int
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case tag, count }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag = try c.req(.tag)
        count = try c.req(.count)
        raw = try JSONValue(from: decoder)
    }
}

/// The target of a relative Markdown link. ``id`` and ``fragment`` are set when ``status`` is `.found`.
public struct LinkResolution: NullDullModel {
    public let status: LinkResolutionStatus
    public let id: String?
    public let fragment: String?
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey { case status, id, fragment }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.req(.status)
        id = try c.opt(.id)
        fragment = try c.opt(.fragment)
        raw = try JSONValue(from: decoder)
    }
}

/// The stored file behind an asset version.
public struct AssetObject: NullDullModel {
    public let id: String
    public let filename: String
    public let mediaType: String
    public let byteSize: Int64
    /// SHA-256, hex.
    public let checksum: String
    public let authorMemberID: String
    /// Unix epoch milliseconds.
    public let createdAt: Int64
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, filename, mediaType, byteSize, checksum, createdAt
        case authorMemberID = "authorMemberId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        filename = try c.req(.filename)
        mediaType = try c.req(.mediaType)
        byteSize = try c.req(.byteSize)
        checksum = try c.req(.checksum)
        authorMemberID = try c.req(.authorMemberID)
        createdAt = try c.req(.createdAt)
        raw = try JSONValue(from: decoder)
    }
}

/// A Memory asset (an image, PDF or other file) with its metadata.
public struct Asset: NullDullModel {
    public let id: String
    public let name: String
    public let scopeID: String
    /// Always `"asset"`.
    public let kind: String
    public let folderID: String?
    /// Root first.
    public let folderPath: [FolderReference]
    public let headRevisionID: String?
    public let revisionID: String?
    public let metadataVersion: Int
    public let role: FileRole
    /// Usage guidance written by people.
    public let description: String
    public let tags: [String]
    public let tagSource: LabelSource
    public let summary: String?
    public let insightStatus: InsightStatus
    /// `nil` until a first version is uploaded.
    public let object: AssetObject?
    public let locationPath: [LocationPathItem]
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, folderPath, metadataVersion, role, description, tags, tagSource
        case summary, insightStatus, object, locationPath
        case scopeID = "scopeId", folderID = "folderId", headRevisionID = "headRevisionId", revisionID = "revisionId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        name = try c.req(.name)
        scopeID = try c.req(.scopeID)
        kind = try c.opt(.kind) ?? "asset"
        folderID = try c.opt(.folderID)
        folderPath = try c.req(.folderPath)
        headRevisionID = try c.opt(.headRevisionID)
        revisionID = try c.opt(.revisionID)
        metadataVersion = try c.req(.metadataVersion)
        role = try c.req(.role)
        description = try c.req(.description)
        tags = try c.req(.tags)
        tagSource = try c.req(.tagSource)
        summary = try c.opt(.summary)
        insightStatus = try c.req(.insightStatus)
        object = try c.opt(.object)
        locationPath = try c.req(.locationPath)
        raw = try JSONValue(from: decoder)
    }
}

/// An immutable asset version.
public struct AssetVersion: NullDullModel {
    public let id: String
    /// Unix epoch milliseconds.
    public let createdAt: Int64
    public let authorMemberID: String
    public let raw: JSONValue

    private enum CodingKeys: String, CodingKey {
        case id, createdAt
        case authorMemberID = "authorMemberId"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.req(.id)
        createdAt = try c.req(.createdAt)
        authorMemberID = try c.req(.authorMemberID)
        raw = try JSONValue(from: decoder)
    }
}
