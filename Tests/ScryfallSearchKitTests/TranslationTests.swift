import Foundation
import Testing
@testable import ScryfallSearchKit

/// A stand-in for a card from an offline database.
private struct FakeCard {
  var name: String
  var typeLine: String
  var cmc: Double
}

private let bolt = FakeCard(name: "Lightning Bolt", typeLine: "Instant", cmc: 1)
private let goblin = FakeCard(name: "Goblin Guide", typeLine: "Creature — Goblin Scout", cmc: 1)
private let elf = FakeCard(name: "Llanowar Elves", typeLine: "Creature — Elf Druid", cmc: 1)
private let krenko = FakeCard(name: "Krenko, Mob Boss", typeLine: "Legendary Creature — Goblin Warrior", cmc: 4)
private let cards = [bolt, goblin, elf, krenko]

/// Supports names, types and mana value; everything else is unsupported.
private func leaf(_ term: ScryfallSearchToken, _ card: FakeCard) -> Bool? {
  switch term {
  case .cardName(let name, let exact):
    exact ? card.name.caseInsensitiveCompare(name) == .orderedSame : card.name.localizedCaseInsensitiveContains(name)
  case .type(let type):
    card.typeLine.localizedCaseInsensitiveContains(type)
  case .stats(.cmc, let quantifier, let value):
    Double(value).map { quantifier.performOn(card.cmc, $0) }
  default:
    nil
  }
}

private func search(_ query: String) -> [String]? {
  guard let token = ScryfallTokenizer().scryfallToken(for: query) else { return nil }
  var names: [String] = []
  for card in cards {
    guard let isMatch = token.matches(card, leaf: leaf) else { return nil }
    if isMatch { names.append(card.name) }
  }
  return names
}

@Suite struct InMemoryMatchingTests {
  @Test func precedenceCarriesThroughToEvaluation() {
    #expect(search("t:legendary t:goblin or t:elf") == ["Llanowar Elves", "Krenko, Mob Boss"])
    #expect(search("t:legendary (t:goblin or t:elf)") == ["Krenko, Mob Boss"])
    #expect(search("-t:creature") == ["Lightning Bolt"])
    #expect(search("-(t:goblin or t:elf)") == ["Lightning Bolt"])
    #expect(search("mv>=2") == ["Krenko, Mob Boss"])
    #expect(search(#"!"lightning bolt""#) == ["Lightning Bolt"])
  }

  @Test func directivesDoNotFilter() {
    #expect(search("unique:prints t:elf") == ["Llanowar Elves"])
    #expect(search("include:extras") == cards.map(\.name))
  }

  @Test func unsupportedTermsAreReportedNotIgnored() {
    #expect(search("t:elf c:g") == nil)
    #expect(search("t:elf or c:g") == nil)
    #expect(search("-c:g") == nil)
  }
}

/// Builds a string predicate, standing in for NSPredicate or SQL.
private struct StringTranslator: ScryfallSearchTokenTranslator {
  func translate(_ term: ScryfallSearchToken) -> String? {
    if case .type(let t) = term { return "type CONTAINS '\(t)'" }
    return nil
  }
  func and(_ lhs: String, _ rhs: String) -> String { "(\(lhs) AND \(rhs))" }
  func or(_ lhs: String, _ rhs: String) -> String { "(\(lhs) OR \(rhs))" }
  func negate(_ operand: String) -> String { "NOT \(operand)" }
  var matchAll: String { "TRUEPREDICATE" }
}

@Suite struct TranslatorTests {
  @Test func translatesStructure() {
    let token = ScryfallTokenizer().scryfallToken(for: "t:legendary t:goblin or -t:elf unique:prints")!
    #expect(token.translated(with: StringTranslator()) ==
      "((type CONTAINS 'legendary' AND type CONTAINS 'goblin') OR NOT type CONTAINS 'elf')")
    #expect(token.directives == ScryfallSearchDirectives(unique: "prints"))
  }

  @Test func onlyDirectivesMatchEverything() {
    let token = ScryfallTokenizer().scryfallToken(for: "unique:art include:extras prefer:oldest")!
    #expect(token.translated(with: StringTranslator()) == "TRUEPREDICATE")
    #expect(token.directives == ScryfallSearchDirectives(unique: "art", include: ["extras"], prefer: .oldest))
  }

  @Test func unsupportedLeafFailsTranslation() {
    let token = ScryfallTokenizer().scryfallToken(for: "t:elf c:g")!
    #expect(token.translated(with: StringTranslator()) == nil)
  }
}
