//
//  ScryfallSearchTokenizer.swift
//  ScryfallSearchKit
//
//  Created by Josh Birnholz on 8/9/22.
//  Copyright © 2022 iowncode. All rights reserved.
//

import Foundation

/// Parses a Scryfall search query string into a ``ScryfallSearchToken`` tree.
///
/// The grammar follows Scryfall's own precedence, which was verified against
/// the live API:
///
/// ```
/// query   := or
/// or      := and ("or" and)*
/// and     := unary+                 // adjacency is an implicit AND; "and" is ignored
/// unary   := "-" unary | primary    // "-" binds tightest
/// primary := "(" or ")" | term
/// term    := key op value | "!" value | value
/// ```
///
/// So `t:legendary t:goblin or t:elf` means `(t:legendary t:goblin) or t:elf`,
/// and `-t:goblin or t:elf` means `(-t:goblin) or t:elf`.
public struct ScryfallTokenizer: Sendable {
  public init() {}

  /// Parses `query`.
  ///
  /// - Parameter ignoreUnrecognized: When `false` (the default), any term the
  ///   token model can't represent makes the whole parse fail and return `nil`.
  ///   When `true`, such terms are kept verbatim as ``ScryfallSearchToken/direct(query:name:humanReadableDescription:)``
  ///   so the query still round-trips.
  /// - Returns: `nil` for an empty query, unbalanced parentheses, a dangling
  ///   operator, or (in strict mode) an unrecognized term.
  public func scryfallToken(for query: String, ignoreUnrecognized: Bool = false) -> ScryfallSearchToken? {
    var lexer = Lexer(query)
    guard let lexemes = lexer.lex() else { return nil }
    var parser = Parser(lexemes: lexemes, ignoreUnrecognized: ignoreUnrecognized)
    return parser.parse()
  }
}

// MARK: - Lexer

enum Lexeme: Equatable {
  case open
  case close
  case not
  case or
  /// `key` `op` `value`, e.g. `t:creature`. `raw` is the text as typed.
  case keyValue(key: String, op: String, value: String, raw: String)
  /// A bare or quoted word, matched against card names.
  case word(String, exact: Bool, raw: String)
}

struct Lexer {
  private let chars: [Character]
  private var index = 0

  init(_ string: String) {
    chars = Array(string)
  }

  private static let operators = [">=", "<=", "!=", "=", ">", "<", ":"]

  private var current: Character? { index < chars.count ? chars[index] : nil }

  private func peek(_ offset: Int) -> Character? {
    let i = index + offset
    return i < chars.count ? chars[i] : nil
  }

  private static func isBreak(_ c: Character) -> Bool {
    c.isWhitespace || c == "(" || c == ")"
  }

  private static func isQuote(_ c: Character) -> Bool {
    c == "\"" || c == "'"
  }

  /// Returns `nil` when a quote or regex is left unterminated.
  mutating func lex() -> [Lexeme]? {
    var result: [Lexeme] = []

    while let c = current {
      if c.isWhitespace {
        index += 1
      } else if c == "(" {
        result.append(.open)
        index += 1
      } else if c == ")" {
        result.append(.close)
        index += 1
      } else if c == "-", let next = peek(1), !next.isWhitespace {
        result.append(.not)
        index += 1
      } else if c == "!", let next = peek(1), !Self.isBreak(next) {
        let start = index
        index += 1
        guard let value = readValue() else { return nil }
        result.append(.word(value, exact: true, raw: String(chars[start..<index])))
      } else {
        guard let lexeme = readTerm() else { return nil }
        result.append(lexeme)
      }
    }

    return result
  }

  private mutating func readTerm() -> Lexeme? {
    let start = index

    // key: a run of letters/digits/underscores immediately followed by an operator.
    var keyEnd = index
    while keyEnd < chars.count, chars[keyEnd].isLetter || chars[keyEnd].isNumber || chars[keyEnd] == "_" {
      keyEnd += 1
    }

    if keyEnd > index, let op = operatorAt(keyEnd) {
      let key = String(chars[index..<keyEnd])
      index = keyEnd + op.count
      guard let value = readValue() else { return nil }
      return .keyValue(key: key, op: op, value: value, raw: String(chars[start..<index]))
    }

    let isQuoted = current.map(Self.isQuote) ?? false
    guard let value = readValue() else { return nil }
    let raw = String(chars[start..<index])

    if !isQuoted {
      switch value.lowercased() {
      case "or": return .or
      // "and" is a no-op: adjacency already means AND. Represent it as an
      // empty word the parser skips.
      case "and": return .word("", exact: false, raw: raw)
      default: break
      }
    }
    return .word(value, exact: false, raw: raw)
  }

  private func operatorAt(_ i: Int) -> String? {
    for op in Self.operators {
      let end = i + op.count
      guard end <= chars.count else { continue }
      if String(chars[i..<end]) == op { return op }
    }
    // Unicode comparison operators, which Scryfall also accepts.
    if i < chars.count {
      switch chars[i] {
      case "≥": return "≥"
      case "≤": return "≤"
      case "≠": return "≠"
      default: break
      }
    }
    return nil
  }

  /// Reads a quoted string, a `/regex/`, or a bare run of characters.
  /// Quoted values are returned without their quotes; regexes keep their slashes.
  private mutating func readValue() -> String? {
    guard let c = current else { return "" }

    if Self.isQuote(c) {
      let quote = c
      index += 1
      var value = ""
      while let ch = current, ch != quote {
        value.append(ch)
        index += 1
      }
      guard current == quote else { return nil } // unterminated
      index += 1
      return value
    }

    if c == "/" {
      var value = "/"
      index += 1
      var escaped = false
      while let ch = current {
        value.append(ch)
        index += 1
        if escaped {
          escaped = false
        } else if ch == "\\" {
          escaped = true
        } else if ch == "/" {
          // Allow trailing characters glued on (rare), up to a break.
          while let tail = current, !Self.isBreak(tail) {
            value.append(tail)
            index += 1
          }
          return value
        }
      }
      return nil // unterminated regex
    }

    var value = ""
    while let ch = current, !Self.isBreak(ch) {
      value.append(ch)
      index += 1
    }
    return value
  }
}

// MARK: - Parser

struct Parser {
  private let lexemes: [Lexeme]
  private var index = 0
  private let ignoreUnrecognized: Bool
  private var failed = false

  init(lexemes: [Lexeme], ignoreUnrecognized: Bool) {
    // Drop the no-op "and" words up front.
    self.lexemes = lexemes.filter {
      if case .word("", false, _) = $0 { return false }
      return true
    }
    self.ignoreUnrecognized = ignoreUnrecognized
  }

  private var current: Lexeme? { index < lexemes.count ? lexemes[index] : nil }

  mutating func parse() -> ScryfallSearchToken? {
    guard !lexemes.isEmpty else { return nil }
    let result = parseOr()
    // Leftover input means a stray ")" or similar.
    guard !failed, index == lexemes.count else { return nil }
    return result
  }

  private mutating func parseOr() -> ScryfallSearchToken? {
    guard var left = parseAnd() else { failed = true; return nil }
    while current == .or {
      index += 1
      guard let right = parseAnd() else { failed = true; return nil }
      left = .or(left, right)
    }
    return left
  }

  private mutating func parseAnd() -> ScryfallSearchToken? {
    var result: ScryfallSearchToken?
    while let lexeme = current, lexeme != .or, lexeme != .close {
      guard let next = parseUnary() else { failed = true; return nil }
      result = result.map { .and($0, next) } ?? next
    }
    return result
  }

  private mutating func parseUnary() -> ScryfallSearchToken? {
    if current == .not {
      index += 1
      guard let operand = parseUnary() else { return nil }
      return .not(operand)
    }
    return parsePrimary()
  }

  private mutating func parsePrimary() -> ScryfallSearchToken? {
    guard let lexeme = current else { return nil }
    index += 1

    switch lexeme {
    case .open:
      guard let inner = parseOr(), current == .close else { return nil }
      index += 1
      return inner
    case .close, .or, .not:
      return nil
    case .word(let value, let exact, _):
      return .cardName(value, exact: exact)
    case .keyValue(let key, let op, let value, let raw):
      if let token = TermMapper.token(key: key, op: op, value: value) {
        return token
      }
      return ignoreUnrecognized ? .direct(query: raw) : nil
    }
  }
}

// MARK: - Term mapping

enum TermMapper {
  static let namedColors: [String: [ScryfallSearchToken.Color]] = [
    "white": [.w], "blue": [.u], "black": [.b], "red": [.r], "green": [.g],
    "colorless": [.c],
    "azorius": [.w, .u], "boros": [.r, .w], "dimir": [.u, .b], "golgari": [.b, .g],
    "gruul": [.r, .g], "izzet": [.u, .r], "orzhov": [.w, .b], "rakdos": [.b, .r],
    "selesnya": [.w, .g], "simic": [.u, .g],
    "abzan": [.w, .b, .g], "bant": [.w, .u, .g], "esper": [.w, .u, .b], "grixis": [.u, .b, .r],
    "jeskai": [.w, .u, .r], "jund": [.b, .r, .g], "mardu": [.w, .b, .r], "naya": [.w, .r, .g],
    "sultai": [.u, .b, .g], "temur": [.u, .r, .g],
    "silverquill": [.w, .b], "prismari": [.u, .r], "witherbloom": [.b, .g],
    "lorehold": [.r, .w], "quandrix": [.g, .u],
    "indatha": [.w, .b, .g], "cabaretti": [.r, .g, .w], "ketria": [.g, .u, .r],
    "obscura": [.w, .u, .b], "raugrin": [.u, .r, .w], "savai": [.r, .w, .b],
    "brokers": [.g, .w, .u], "maestros": [.u, .b, .r], "zagoth": [.b, .g, .u],
    "riveteers": [.b, .r, .g],
  ]

  /// Parses a color string like `wub` or a guild/shard name. Returns `[]` if
  /// any character isn't a color.
  static func colors(in value: String) -> [ScryfallSearchToken.Color] {
    if let named = namedColors[value.lowercased()] { return named }
    var result: [ScryfallSearchToken.Color] = []
    for character in value.uppercased() {
      guard let color = ScryfallSearchToken.Color(rawValue: String(character)) else { return [] }
      if !result.contains(color) { result.append(color) }
    }
    return result
  }

  private static func isEquality(_ op: String) -> Bool { op == ":" || op == "=" }

  /// Maps one `key op value` term to a token, or `nil` when the token model
  /// can't represent it.
  static func token(key rawKey: String, op rawOp: String, value: String) -> ScryfallSearchToken? {
    typealias Q = ScryfallSearchToken.Quantifier
    let key = rawKey.lowercased()
    let op: String = switch rawOp {
    case "≥": ">="
    case "≤": "<="
    case "≠": "!="
    default: rawOp
    }
    let lowerValue = value.lowercased()

    func quantifier(colon: Q) -> Q? { Q(value: op, valueForColon: colon) }

    if let legality = ScryfallSearchToken.Legality(rawValue: key) {
      guard isEquality(op), !value.isEmpty else { return nil }
      return .legal(legality, value)
    }

    switch key {
    case "c", "color", "commander", "id", "identity", "ci":
      let choice: ScryfallSearchToken.ColorChoice = ["c", "color"].contains(key) ? .color : .identity
      if let count = Int(value) {
        guard let q = quantifier(colon: .exactly) else { return nil }
        return .colorCount(choice, count, q)
      }
      let colors = colors(in: value)
      guard !colors.isEmpty else { return nil }
      let colon: Q = colors == [.c] ? .exactly : (choice == .color ? .including : .atMost)
      guard let q = quantifier(colon: colon) else { return nil }
      return .colors(choice, colors, q)

    case "t", "type":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .type(value)

    case "o", "oracle":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .oracleContains(value)

    case "name":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .cardName(value)

    case "m", "mana":
      guard !value.isEmpty, let q = quantifier(colon: .including) else { return nil }
      return .manaCost(value, q)

    case "pow", "power", "tou", "toughness", "loy", "loyalty", "cmc", "mv", "manavalue":
      guard !value.isEmpty, let q = quantifier(colon: .exactly) else { return nil }
      let stat: ScryfallSearchToken.Stat = switch key {
      case "pow", "power": .power
      case "tou", "toughness": .toughness
      case "loy", "loyalty": .loyalty
      default: .cmc
      }
      return .stats(stat, q, value)

    case "usd", "eur", "tix":
      guard !value.isEmpty, let currency = Currency(rawValue: key), let q = quantifier(colon: .exactly) else { return nil }
      return .price(currency, q, value)

    case "cn", "number", "collectornumber", "collector":
      guard !value.isEmpty, let q = quantifier(colon: .exactly) else { return nil }
      return .collectorNumber(q, value)

    case "year":
      guard !value.isEmpty, let q = quantifier(colon: .exactly) else { return nil }
      return .year(q, value)

    case "artists":
      guard !value.isEmpty, let q = quantifier(colon: .exactly) else { return nil }
      return .artists(q, value)

    case "devotion":
      guard !value.isEmpty, let q = quantifier(colon: .including) else { return nil }
      return .devotion(q, value)

    case "is", "has":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .criterion(value)

    case "not":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .not(.criterion(value))

    case "r", "rarity":
      guard let q = quantifier(colon: .exactly) else { return nil }
      guard let rarity = ScryfallSearchToken.Rarity(rawValue: lowerValue)
              ?? (lowerValue.count == 1 ? ScryfallSearchToken.Rarity.allCases.first(where: { $0.rawValue.first.map(String.init) == lowerValue }) : nil)
      else { return nil }
      return .rarity(rarity, q)

    case "s", "e", "set", "edition":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .sets(value.components(separatedBy: ","))

    case "b", "block":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .blocks(value.components(separatedBy: ","))

    case "st", "settype":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .setType(value)

    case "in":
      guard isEquality(op), !value.isEmpty else { return nil }
      // Spellbook-specific: "in:collection" means cards you own.
      if lowerValue == "collection" { return .criterion("owned") }
      return .in(value)

    case "kw", "keyword":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .keyword(value)

    case "a", "artist":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .artist(value)

    case "wm", "watermark":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .watermark(value)

    case "border":
      guard isEquality(op), let color = ScryfallSearchToken.BorderColor(rawValue: lowerValue) else { return nil }
      return .border(color)

    case "ft", "flavor":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .flavorText(value)

    case "lore":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .lore(value)

    case "include":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .include(value)

    case "unique":
      guard isEquality(op), ["cards", "prints", "art"].contains(lowerValue) else { return nil }
      return .unique(lowerValue)

    case "f", "format":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .legal(.legal, value)

    case "lang", "language":
      guard isEquality(op), !value.isEmpty else { return nil }
      return lowerValue == "any" ? .language(.any) : .language(.language(ScryfallLanguage(rawValue: lowerValue)))

    case "new":
      guard isEquality(op), let new = ScryfallSearchToken.New(rawValue: lowerValue) else { return nil }
      return .new(new)

    case "cheapest":
      guard isEquality(op), let currency = Currency(rawValue: lowerValue) else { return nil }
      return .cheapest(currency)

    case "cube":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .cube(value)

    case "frame":
      guard isEquality(op), let frame = ScryfallSearchToken.Frame(rawValue: lowerValue) else { return nil }
      return .frame(frame)

    case "stamp":
      guard isEquality(op), let stamp = ScryfallSecurityStamp(rawValue: lowerValue) else { return nil }
      return .stamp(stamp)

    case "game":
      guard isEquality(op), let game = ScryfallSearchToken.Game(rawValue: lowerValue) else { return nil }
      return .game(game)

    case "prefer":
      guard isEquality(op), let prefer = ScryfallSearchToken.Prefer(rawValue: lowerValue) else { return nil }
      return .prefer(prefer)

    case "art", "atag", "arttag":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .art(value)

    case "function", "otag", "oracletag":
      guard isEquality(op), !value.isEmpty else { return nil }
      return .function(value)

    case "owned":
      // Spellbook-specific: number of copies in your collection.
      guard let count = Int(value), let q = quantifier(colon: .including) else { return nil }
      return .owned(count, q)

    default:
      return nil
    }
  }
}
