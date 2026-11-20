import Foundation
import XCTest

@testable import NullDullGrid

/// The shared Grid renderer fixtures, read in place from the repository's `fixtures/grid-renderer`
/// directory (shared with the Kotlin renderer's tests), found relative to this source file.
enum Fixtures {
  static let root: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // NullDullGridTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // swift
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("fixtures/grid-renderer")

  static func data(_ path: String) throws -> Data {
    try Data(contentsOf: root.appendingPathComponent(path))
  }

  static func json(_ path: String) throws -> JSONValue {
    try JSONValue.parse(data(path))
  }

  static var documentNames: [String] {
    let directory = root.appendingPathComponent("documents")
    let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
  }

  static func document(_ name: String) throws -> GridDocument {
    try GridDocument(json: data("documents/\(name).json"))
  }
}

extension JSONValue {
  var double: Double? {
    if case .number(let value) = self { return value }
    return nil
  }
  var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }
  var bool: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }
  var array: [JSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }
  var object: JSONObject? {
    if case .object(let value) = self { return value }
    return nil
  }

  /// Structural equality that ignores object key order.
  func sameValue(as other: JSONValue) -> Bool {
    switch (self, other) {
    case (.object(let a), .object(let b)):
      return Set(a.keys) == Set(b.keys) && a.keys.allSatisfy { a[$0]!.sameValue(as: b[$0]!) }
    case (.array(let a), .array(let b)):
      return a.count == b.count && zip(a, b).allSatisfy { $0.sameValue(as: $1) }
    default:
      return self == other
    }
  }
}
