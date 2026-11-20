import Foundation

/// A JSON value with JavaScript's distinctions intact: a missing key, `null`,
/// booleans and numbers are all different. Validation runs on this tree so it
/// can match `@nulldull/grid-core`'s `validateGrid` check for check.
public enum JSONValue: Hashable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  /// Keys keep their source order, as JavaScript objects do for string keys.
  case object(JSONObject)

  public subscript(key: String) -> JSONValue? {
    if case .object(let object) = self { return object[key] }
    return nil
  }
}

/// An insertion-ordered JSON object.
public struct JSONObject: Hashable, Sendable {
  public private(set) var keys: [String] = []
  private var values: [String: JSONValue] = [:]

  public init() {}
  public init(_ pairs: [(String, JSONValue)]) {
    for (key, value) in pairs { self[key] = value }
  }
  public subscript(key: String) -> JSONValue? {
    get { values[key] }
    set {
      if let newValue {
        if values.updateValue(newValue, forKey: key) == nil { keys.append(key) }
      } else if values.removeValue(forKey: key) != nil {
        keys.removeAll { $0 == key }
      }
    }
  }
  public var pairs: [(String, JSONValue)] { keys.map { ($0, values[$0]!) } }
  public var count: Int { keys.count }
}

extension JSONValue: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() { self = .null; return }
    if let value = try? container.decode(Bool.self) { self = .bool(value); return }
    if let value = try? container.decode(Double.self) { self = .number(value); return }
    if let value = try? container.decode(String.self) { self = .string(value); return }
    if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
    // Keyed containers lose key order, so objects are decoded through JSONSerialization
    // in `JSONValue.parse`; this path keeps Codable composition working.
    let keyed = try decoder.container(keyedBy: AnyKey.self)
    var object = JSONObject()
    for key in keyed.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
      object[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key)
    }
    self = .object(object)
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .null:
      var container = encoder.singleValueContainer()
      try container.encodeNil()
    case .bool(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .number(let value):
      var container = encoder.singleValueContainer()
      if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
        try container.encode(Int64(value))
      } else {
        try container.encode(value)
      }
    case .string(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .array(let values):
      var container = encoder.unkeyedContainer()
      for value in values { try container.encode(value) }
    case .object(let object):
      var container = encoder.container(keyedBy: AnyKey.self)
      for (key, value) in object.pairs { try container.encode(value, forKey: AnyKey(key)) }
    }
  }
}

struct AnyKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }
  init(_ string: String) { stringValue = string }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}

extension JSONValue {
  /// Parses JSON text, preserving object key order and the bool/number distinction.
  public static func parse(_ data: Data) throws -> JSONValue {
    var parser = OrderedJSONParser(bytes: Array(data))
    return try parser.parseDocument()
  }

  public static func parse(_ text: String) throws -> JSONValue {
    try parse(Data(text.utf8))
  }

  /// Serializes like JavaScript's `JSON.stringify` (no whitespace, shortest numbers,
  /// the same string escapes), so byte counts match the TypeScript size limit.
  public var javaScriptJSON: String {
    var out = ""
    write(into: &out)
    return out
  }

  private func write(into out: inout String) {
    switch self {
    case .null: out += "null"
    case .bool(let value): out += value ? "true" : "false"
    case .number(let value): out += JSONValue.javaScriptNumber(value)
    case .string(let value): JSONValue.writeString(value, into: &out)
    case .array(let values):
      out += "["
      for (index, value) in values.enumerated() {
        if index > 0 { out += "," }
        value.write(into: &out)
      }
      out += "]"
    case .object(let object):
      out += "{"
      for (index, (key, value)) in object.pairs.enumerated() {
        if index > 0 { out += "," }
        JSONValue.writeString(key, into: &out)
        out += ":"
        value.write(into: &out)
      }
      out += "}"
    }
  }

  static func javaScriptNumber(_ value: Double) -> String {
    guard value.isFinite else { return "null" }
    if value == 0 { return "0" }
    if value.rounded() == value, abs(value) < 1e21 {
      return String(format: "%.0f", value)
    }
    // Swift's description is the shortest round-tripping form, as in JavaScript;
    // only the exponent spelling differs ("1e-07" versus "1e-7").
    var text = "\(value)"
    if let e = text.firstIndex(of: "e") {
      let mantissa = text[..<e]
      var exponent = String(text[text.index(after: e)...])
      let negative = exponent.hasPrefix("-")
      exponent = exponent.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
      while exponent.hasPrefix("0") && exponent.count > 1 { exponent.removeFirst() }
      text = "\(mantissa)e\(negative ? "-" : "+")\(exponent)"
    }
    return text
  }

  static func writeString(_ value: String, into out: inout String) {
    out += "\""
    for unit in value.unicodeScalars {
      switch unit {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case "\u{08}": out += "\\b"
      case "\u{0C}": out += "\\f"
      default:
        if unit.value < 0x20 {
          out += String(format: "\\u%04x", unit.value)
        } else {
          out.unicodeScalars.append(unit)
        }
      }
    }
    out += "\""
  }
}

/// A small RFC 8259 parser. Foundation's JSONSerialization neither keeps key
/// order nor reliably distinguishes `true` from `1` across platforms.
struct OrderedJSONParser {
  let bytes: [UInt8]
  var index = 0

  struct Failure: Error, CustomStringConvertible {
    let offset: Int
    var description: String { "Invalid JSON at byte \(offset)." }
  }

  mutating func parseDocument() throws -> JSONValue {
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
    let value = try parseValue(depth: 0)
    skipWhitespace()
    guard index == bytes.count else { throw Failure(offset: index) }
    return value
  }

  mutating func skipWhitespace() {
    while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
  }

  mutating func parseValue(depth: Int) throws -> JSONValue {
    guard depth < 512 else { throw Failure(offset: index) }
    skipWhitespace()
    guard index < bytes.count else { throw Failure(offset: index) }
    switch bytes[index] {
    case UInt8(ascii: "{"):
      index += 1
      var object = JSONObject()
      skipWhitespace()
      if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
      while true {
        skipWhitespace()
        guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw Failure(offset: index) }
        let key = try parseString()
        skipWhitespace()
        guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw Failure(offset: index) }
        index += 1
        // Like JSON.parse, a repeated key keeps its first position and last value.
        object[key] = try parseValue(depth: depth + 1)
        skipWhitespace()
        guard index < bytes.count else { throw Failure(offset: index) }
        if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
        if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
        throw Failure(offset: index)
      }
    case UInt8(ascii: "["):
      index += 1
      var values: [JSONValue] = []
      skipWhitespace()
      if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(values) }
      while true {
        values.append(try parseValue(depth: depth + 1))
        skipWhitespace()
        guard index < bytes.count else { throw Failure(offset: index) }
        if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
        if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(values) }
        throw Failure(offset: index)
      }
    case UInt8(ascii: "\""):
      return .string(try parseString())
    case UInt8(ascii: "t"):
      try expect("true"); return .bool(true)
    case UInt8(ascii: "f"):
      try expect("false"); return .bool(false)
    case UInt8(ascii: "n"):
      try expect("null"); return .null
    default:
      return .number(try parseNumber())
    }
  }

  mutating func expect(_ word: String) throws {
    let utf8 = Array(word.utf8)
    guard index + utf8.count <= bytes.count, Array(bytes[index..<index + utf8.count]) == utf8 else {
      throw Failure(offset: index)
    }
    index += utf8.count
  }

  mutating func parseNumber() throws -> Double {
    let start = index
    if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
    func digits() -> Int {
      let from = index
      while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
      return index - from
    }
    guard index < bytes.count else { throw Failure(offset: index) }
    if bytes[index] == UInt8(ascii: "0") { index += 1 } else if digits() == 0 { throw Failure(offset: index) }
    if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
      index += 1
      guard digits() > 0 else { throw Failure(offset: index) }
    }
    if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
      index += 1
      if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
      guard digits() > 0 else { throw Failure(offset: index) }
    }
    let text = String(decoding: bytes[start..<index], as: UTF8.self)
    // Overflow becomes ±Infinity, as in JSON.parse; validation then rejects it.
    guard let value = Double(text) else { throw Failure(offset: start) }
    return value
  }

  mutating func parseString() throws -> String {
    index += 1
    var scalars = String.UnicodeScalarView()
    var pendingHigh: UInt32?
    func flushHigh() {
      if pendingHigh != nil { scalars.append("\u{FFFD}"); pendingHigh = nil }
    }
    var run = index
    func appendRun(_ end: Int) throws {
      guard run < end else { return }
      flushHigh()
      guard let text = String(bytes: bytes[run..<end], encoding: .utf8) else { throw Failure(offset: run) }
      scalars.append(contentsOf: text.unicodeScalars)
    }
    while true {
      guard index < bytes.count else { throw Failure(offset: index) }
      let byte = bytes[index]
      if byte == UInt8(ascii: "\"") {
        try appendRun(index)
        flushHigh()
        index += 1
        return String(scalars)
      }
      if byte < 0x20 { throw Failure(offset: index) }
      if byte != UInt8(ascii: "\\") { index += 1; continue }
      try appendRun(index)
      index += 1
      guard index < bytes.count else { throw Failure(offset: index) }
      let escape = bytes[index]
      index += 1
      if escape == UInt8(ascii: "u") {
        guard index + 4 <= bytes.count,
          let code = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16)
        else { throw Failure(offset: index) }
        index += 4
        if (0xD800...0xDBFF).contains(code) {
          flushHigh()
          pendingHigh = code
        } else if (0xDC00...0xDFFF).contains(code) {
          if let high = pendingHigh {
            scalars.append(Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (code - 0xDC00))!)
            pendingHigh = nil
          } else {
            scalars.append("\u{FFFD}")
          }
        } else {
          flushHigh()
          scalars.append(Unicode.Scalar(code)!)
        }
      } else {
        flushHigh()
        switch escape {
        case UInt8(ascii: "\""): scalars.append("\"")
        case UInt8(ascii: "\\"): scalars.append("\\")
        case UInt8(ascii: "/"): scalars.append("/")
        case UInt8(ascii: "b"): scalars.append("\u{08}")
        case UInt8(ascii: "f"): scalars.append("\u{0C}")
        case UInt8(ascii: "n"): scalars.append("\n")
        case UInt8(ascii: "r"): scalars.append("\r")
        case UInt8(ascii: "t"): scalars.append("\t")
        default: throw Failure(offset: index - 1)
        }
      }
      run = index
    }
  }
}
