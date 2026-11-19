import Foundation

private func isLowerAlnum(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
}

private func isLowerHex(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
}

/// `^nd_(pub|sec)_[a-f0-9]{64}$`
func isAPIKey(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count == 71, value.hasPrefix("nd_pub_") || value.hasPrefix("nd_sec_") else { return false }
    return bytes[7...].allSatisfy(isLowerHex)
}

/// `^[a-zA-Z0-9_-]{1,128}$`
func isWorkspaceID(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard (1...128).contains(bytes.count) else { return false }
    return bytes.allSatisfy { byte in
        isLowerAlnum(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
    }
}

/// Pools and slugs: `^[a-z0-9]+(?:-[a-z0-9]+)*$`, at most 96 characters.
func isGridKey(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard (1...96).contains(bytes.count) else { return false }
    let parts = bytes.split(separator: UInt8(ascii: "-"), omittingEmptySubsequences: false)
    return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(isLowerAlnum) }
}

/// `^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$`, at most 35 characters.
func isGridLocale(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard (1...35).contains(bytes.count) else { return false }
    let parts = bytes.split(separator: UInt8(ascii: "-"), omittingEmptySubsequences: false)
    guard let first = parts.first, (2...3).contains(first.count),
        first.allSatisfy({ (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) })
    else { return false }
    return parts.dropFirst().allSatisfy { (2...8).contains($0.count) && $0.allSatisfy(isLowerAlnum) }
}

/// A non-empty ID, percent-encoded as one path segment.
func pathSegment(_ value: String, _ name: String) throws -> String {
    guard !value.isEmpty else { throw NullDullError.invalidArgument("\(name) must be a non-empty string.") }
    return percentEncode(value)
}
