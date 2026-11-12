//
//  ScryfallSearchToken+Translation.swift
//  ScryfallSearchKit
//
//  Hooks for evaluating a token tree without Scryfall, e.g. against an
//  offline copy of the card database. The package handles the boolean
//  structure (AND / OR / NOT / parentheses) and search directives; the
//  caller only supplies what each leaf term means for its storage.
//

import Foundation

/// Turns the leaves of a token tree into some storage-specific form and
/// combines them.
///
/// `Output` might be an `NSPredicate` (Core Data), a SwiftData `Predicate`,
/// a SQL `WHERE` fragment, or a `(Card) -> Bool` closure for in-memory
/// filtering.
public protocol ScryfallSearchTokenTranslator {
  associatedtype Output

  /// The translation of one leaf term, such as `.type("elf")` or
  /// `.stats(.power, .including, "3")`. Return `nil` if the term isn't
  /// supported, which makes the whole translation fail rather than silently
  /// returning wrong results.
  ///
  /// Never called with `.and`, `.or`, `.not`, `.parentheses`, or a
  /// directive (see ``ScryfallSearchToken/isDirective``). Negations arrive
  /// as ``negate(_:)`` applied to the operand's translation.
  func translate(_ term: ScryfallSearchToken) -> Output?

  func and(_ lhs: Output, _ rhs: Output) -> Output
  func or(_ lhs: Output, _ rhs: Output) -> Output
  func negate(_ operand: Output) -> Output

  /// The output for a query that is only directives (e.g. `unique:prints`),
  /// which matches every card.
  var matchAll: Output { get }
}

/// Settings a query carries that aren't card filters, such as `unique:prints`
/// or `include:extras`. An offline search applies these to the result set.
public struct ScryfallSearchDirectives: Equatable, Sendable {
  /// `unique:` value (`cards`, `prints` or `art`), lowercased.
  public var unique: String?
  /// `include:` values, lowercased (e.g. `extras`).
  public var include: Set<String> = []
  public var prefer: ScryfallSearchToken.Prefer?

  public init(unique: String? = nil, include: Set<String> = [], prefer: ScryfallSearchToken.Prefer? = nil) {
    self.unique = unique
    self.include = include
    self.prefer = prefer
  }
}

extension ScryfallSearchToken {
  /// Whether this token changes how results are returned rather than which
  /// cards match: `unique:`, `include:` and `prefer:`.
  public var isDirective: Bool {
    switch self {
    case .unique, .include, .prefer: true
    default: false
    }
  }

  /// The directives anywhere in the tree. Scryfall applies them globally, even
  /// inside parentheses or an OR.
  public var directives: ScryfallSearchDirectives {
    var result = ScryfallSearchDirectives()
    for token in allBaseTokens {
      switch token {
      case .unique(let value): result.unique = value.lowercased()
      case .include(let value): result.include.insert(value.lowercased())
      case .prefer(let value): result.prefer = value
      default: break
      }
    }
    return result
  }

  /// The tree with directives removed, or `nil` if nothing but directives
  /// remains. A NOT or OR whose operand was only a directive drops out too.
  public var filterToken: ScryfallSearchToken? {
    switch self {
    case _ where isDirective:
      return nil
    case .and(let lhs, let rhs):
      switch (lhs.filterToken, rhs.filterToken) {
      case let (l?, r?): return .and(l, r)
      case let (l?, nil): return l
      case let (nil, r?): return r
      case (nil, nil): return nil
      }
    case .or(let lhs, let rhs):
      switch (lhs.filterToken, rhs.filterToken) {
      case let (l?, r?): return .or(l, r)
      case let (l?, nil): return l
      case let (nil, r?): return r
      case (nil, nil): return nil
      }
    case .not(let operand):
      return operand.filterToken.map { .not($0) }
    case .parentheses(let inner):
      return inner.filterToken
    default:
      return self
    }
  }

  /// Translates the card-filtering part of this tree with `translator`.
  ///
  /// Directives are skipped (read them from ``directives``). Returns `nil` if
  /// any leaf is unsupported, or if the tree contains a `.direct` query the
  /// translator doesn't handle; parse with `ignoreUnrecognized: false` to
  /// reject unknown syntax up front.
  public func translated<T: ScryfallSearchTokenTranslator>(with translator: T) -> T.Output? {
    guard let filter = filterToken else { return translator.matchAll }
    return filter.translateFilter(with: translator)
  }

  private func translateFilter<T: ScryfallSearchTokenTranslator>(with translator: T) -> T.Output? {
    switch self {
    case .and(let lhs, let rhs):
      guard let l = lhs.translateFilter(with: translator), let r = rhs.translateFilter(with: translator) else { return nil }
      return translator.and(l, r)
    case .or(let lhs, let rhs):
      guard let l = lhs.translateFilter(with: translator), let r = rhs.translateFilter(with: translator) else { return nil }
      return translator.or(l, r)
    case .not(let operand):
      return operand.translateFilter(with: translator).map(translator.negate)
    case .parentheses(let inner):
      return inner.translateFilter(with: translator)
    default:
      return translator.translate(self)
    }
  }
}

extension ScryfallSearchToken {
  /// Evaluates the tree in memory against `subject` (for example, a card
  /// decoded from an offline bulk-data file), using `leaf` for each term.
  ///
  /// ```swift
  /// let isMatch = token.matches(card) { term, card in
  ///   switch term {
  ///   case .type(let t): card.typeLine.localizedCaseInsensitiveContains(t)
  ///   default: nil // unsupported
  ///   }
  /// }
  /// ```
  ///
  /// Returns `nil` if `leaf` returns `nil` (unsupported) for any term the
  /// tree contains, so callers can fall back to an online search.
  public func matches<Subject>(_ subject: Subject, leaf: (ScryfallSearchToken, Subject) -> Bool?) -> Bool? {
    guard let filter = filterToken else { return true }
    return filter.evaluate(subject, leaf: leaf)
  }

  private func evaluate<Subject>(_ subject: Subject, leaf: (ScryfallSearchToken, Subject) -> Bool?) -> Bool? {
    switch self {
    case .and(let lhs, let rhs):
      // Evaluate both sides so an unsupported term is always reported.
      guard let l = lhs.evaluate(subject, leaf: leaf), let r = rhs.evaluate(subject, leaf: leaf) else { return nil }
      return l && r
    case .or(let lhs, let rhs):
      guard let l = lhs.evaluate(subject, leaf: leaf), let r = rhs.evaluate(subject, leaf: leaf) else { return nil }
      return l || r
    case .not(let operand):
      return operand.evaluate(subject, leaf: leaf).map(!)
    case .parentheses(let inner):
      return inner.evaluate(subject, leaf: leaf)
    default:
      return leaf(self, subject)
    }
  }
}
