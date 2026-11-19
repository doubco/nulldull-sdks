import Foundation

/// The kind of a Memory location.
public enum LocationKind: NullDullOpenEnum {
    case workspace, customerProduct, project
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "workspace": self = .workspace
        case "customer-product": self = .customerProduct
        case "project": self = .project
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .workspace: "workspace"
        case .customerProduct: "customer-product"
        case .project: "project"
        case .unknown(let value): value
        }
    }
}

/// How a location icon is drawn.
public enum IconKind: NullDullOpenEnum {
    case symbol, emoji, image
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "symbol": self = .symbol
        case "emoji": self = .emoji
        case "image": self = .image
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .symbol: "symbol"
        case .emoji: "emoji"
        case .image: "image"
        case .unknown(let value): value
        }
    }
}

/// A document's kind label. Also a `listDocuments`/`search` filter.
public enum FileKind: NullDullOpenEnum {
    case rules, tasks, plan, reference, procedure, notes
    /// The literal `"unknown"` kind the API uses for unclassified files.
    case unclassified
    /// A kind added after this SDK was released.
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "rules": self = .rules
        case "tasks": self = .tasks
        case "plan": self = .plan
        case "reference": self = .reference
        case "procedure": self = .procedure
        case "notes": self = .notes
        case "unknown": self = .unclassified
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .rules: "rules"
        case .tasks: "tasks"
        case .plan: "plan"
        case .reference: "reference"
        case .procedure: "procedure"
        case .notes: "notes"
        case .unclassified: "unknown"
        case .unknown(let value): value
        }
    }
}

/// A document's lifecycle label. Also a `listDocuments`/`search` filter.
public enum FileLifecycle: NullDullOpenEnum {
    case maintained, oneTime
    /// The literal `"unknown"` lifecycle the API uses for unclassified files.
    case unclassified
    /// A lifecycle added after this SDK was released.
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "maintained": self = .maintained
        case "one-time": self = .oneTime
        case "unknown": self = .unclassified
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .maintained: "maintained"
        case .oneTime: "one-time"
        case .unclassified: "unknown"
        case .unknown(let value): value
        }
    }
}

/// A file's role.
public enum FileRole: NullDullOpenEnum {
    case senior, junior
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "senior": self = .senior
        case "junior": self = .junior
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .senior: "senior"
        case .junior: "junior"
        case .unknown(let value): value
        }
    }
}

/// Who set a label or tag.
public enum LabelSource: NullDullOpenEnum {
    case ai, manual
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "ai": self = .ai
        case "manual": self = .manual
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .ai: "ai"
        case .manual: "manual"
        case .unknown(let value): value
        }
    }
}

/// Where automatic labelling stands for a file.
public enum LabelStatus: NullDullOpenEnum {
    case ready, pending, failed, unclassified
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "ready": self = .ready
        case "pending": self = .pending
        case "failed": self = .failed
        case "unclassified": self = .unclassified
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .ready: "ready"
        case .pending: "pending"
        case .failed: "failed"
        case .unclassified: "unclassified"
        case .unknown(let value): value
        }
    }
}

/// Whether a folder's contents are visible to the key's member.
public enum FolderContents: NullDullOpenEnum {
    case empty, visible, hidden
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "empty": self = .empty
        case "visible": self = .visible
        case "hidden": self = .hidden
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .empty: "empty"
        case .visible: "visible"
        case .hidden: "hidden"
        case .unknown(let value): value
        }
    }
}

/// Where an asset's AI summary stands.
public enum InsightStatus: NullDullOpenEnum {
    case ready, pending, failed, unavailable
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "ready": self = .ready
        case "pending": self = .pending
        case "failed": self = .failed
        case "unavailable": self = .unavailable
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .ready: "ready"
        case .pending: "pending"
        case .failed: "failed"
        case .unavailable: "unavailable"
        case .unknown(let value): value
        }
    }
}

/// The outcome of ``MemoryAPI/resolveLink(_:href:)``.
public enum LinkResolutionStatus: NullDullOpenEnum {
    case found, unavailable, ambiguous
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "found": self = .found
        case "unavailable": self = .unavailable
        case "ambiguous": self = .ambiguous
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .found: "found"
        case .unavailable: "unavailable"
        case .ambiguous: "ambiguous"
        case .unknown(let value): value
        }
    }
}

/// A Locale export format. Unknown IDs are sent as given; the server answers `400` with
/// `detail: LOCALE_FORMAT_UNKNOWN`.
public enum LocaleFormatID: NullDullOpenEnum, ExpressibleByStringLiteral {
    case json, world, worldCLDR, xcstrings, appleStrings, androidXML
    case unknown(String)

    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public init(rawValue: String) {
        switch rawValue {
        case "json": self = .json
        case "world": self = .world
        case "world-cldr": self = .worldCLDR
        case "xcstrings": self = .xcstrings
        case "apple-strings": self = .appleStrings
        case "android-xml": self = .androidXML
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .json: "json"
        case .world: "world"
        case .worldCLDR: "world-cldr"
        case .xcstrings: "xcstrings"
        case .appleStrings: "apple-strings"
        case .androidXML: "android-xml"
        case .unknown(let value): value
        }
    }
}

/// A Locale key's review status.
public enum LocaleKeyStatus: NullDullOpenEnum, ExpressibleByStringLiteral {
    case draft, needsReview, approved
    case unknown(String)

    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public init(rawValue: String) {
        switch rawValue {
        case "draft": self = .draft
        case "needs_review": self = .needsReview
        case "approved": self = .approved
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .draft: "draft"
        case .needsReview: "needs_review"
        case .approved: "approved"
        case .unknown(let value): value
        }
    }
}

/// `single`: one file set per language. `multi`: one file holds every language.
public enum LocaleLayout: NullDullOpenEnum {
    case single, multi
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "single": self = .single
        case "multi": self = .multi
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .single: "single"
        case .multi: "multi"
        case .unknown(let value): value
        }
    }
}

/// How a Locale format represents plurals.
public enum LocalePlurals: NullDullOpenEnum {
    case cldr, oneOther
    /// The wire value `none`: the format has no plural forms. (Named so it never reads as `Optional.none`.)
    case unsupported
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "cldr": self = .cldr
        case "one-other": self = .oneOther
        case "none": self = .unsupported
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .cldr: "cldr"
        case .oneOther: "one-other"
        case .unsupported: "none"
        case .unknown(let value): value
        }
    }
}

/// How a Locale format writes variables.
public enum LocaleVariables: NullDullOpenEnum {
    case named, positional
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "named": self = .named
        case "positional": self = .positional
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .named: "named"
        case .positional: "positional"
        case .unknown(let value): value
        }
    }
}
