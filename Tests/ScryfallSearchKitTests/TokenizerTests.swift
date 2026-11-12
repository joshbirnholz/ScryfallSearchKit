import Foundation
import Testing
@testable import ScryfallSearchKit

private let tokenizer = ScryfallTokenizer()

private func parse(_ query: String, lenient: Bool = false) -> ScryfallSearchToken? {
  tokenizer.scryfallToken(for: query, ignoreUnrecognized: lenient)
}

// MARK: - Precedence

@Suite struct PrecedenceTests {
  @Test func andBindsTighterThanOr() {
    // Scryfall: 765 cards, i.e. (legendary goblin) OR elf, not legendary AND (goblin OR elf).
    #expect(parse("t:legendary t:goblin or t:elf") == .or(.and(.type("legendary"), .type("goblin")), .type("elf")))
    #expect(parse("t:elf or t:legendary t:goblin") == .or(.type("elf"), .and(.type("legendary"), .type("goblin"))))
  }

  @Test func parenthesesOverridePrecedence() {
    #expect(parse("t:legendary (t:goblin or t:elf)") == .and(.type("legendary"), .or(.type("goblin"), .type("elf"))))
  }

  @Test func orOfGroups() {
    // The old tokenizer flattened parentheses by depth and failed here.
    #expect(parse("(t:elf t:warrior) or (t:goblin t:shaman)") ==
      .or(.and(.type("elf"), .type("warrior")), .and(.type("goblin"), .type("shaman"))))
    #expect(parse("t:elf or (t:goblin t:shaman)") == .or(.type("elf"), .and(.type("goblin"), .type("shaman"))))
  }

  @Test func nestedParentheses() {
    #expect(parse("((t:elf or t:goblin) c:g) or t:dragon") ==
      .or(.and(.or(.type("elf"), .type("goblin")), .colors(.color, [.g], .including)), .type("dragon")))
  }

  @Test func notBindsTightest() {
    #expect(parse("-t:goblin or t:elf") == .or(.not(.type("goblin")), .type("elf")))
    #expect(parse("-t:creature t:artifact") == .and(.not(.type("creature")), .type("artifact")))
    #expect(parse("-(t:creature t:artifact)") == .not(.and(.type("creature"), .type("artifact"))))
    #expect(parse("--t:elf") == .not(.not(.type("elf"))))
  }

  @Test func orChainsAreLeftAssociative() {
    #expect(parse("t:a or t:b or t:c") == .or(.or(.type("a"), .type("b")), .type("c")))
  }

  @Test func andKeywordIsIgnored() {
    #expect(parse("t:elf and t:warrior") == .and(.type("elf"), .type("warrior")))
    #expect(parse("t:elf AND t:warrior") == parse("t:elf t:warrior"))
  }

  @Test func orIsCaseInsensitive() {
    #expect(parse("t:elf OR t:goblin") == parse("t:elf or t:goblin"))
  }
}

// MARK: - Lexing

@Suite struct LexingTests {
  @Test func quotedValues() {
    #expect(parse(#"o:"draw a card""#) == .oracleContains("draw a card"))
    #expect(parse("o:'draw a card'") == .oracleContains("draw a card"))
    #expect(parse(#"o:'"quoted"'"#) == .oracleContains(#""quoted""#))
    #expect(parse(#"t:"legendary creature" c:r"#) == .and(.type("legendary creature"), .colors(.color, [.r], .including)))
  }

  @Test func parenthesesInsideQuotesAreLiteral() {
    #expect(parse(#"o:"(this is reminder text)""#) == .oracleContains("(this is reminder text)"))
  }

  @Test func regexValuesKeepSpaces() {
    #expect(parse("o:/draw a card/") == .oracleContains("/draw a card/"))
    #expect(parse(#"o:/^\{T\}: add/ t:land"#) == .and(.oracleContains(#"/^\{T\}: add/"#), .type("land")))
  }

  @Test func apostrophesInBareWords() {
    // The old regex split "urza's" into "urza" and "s".
    #expect(parse("urza's tower") == .and(.cardName("urza's"), .cardName("tower")))
  }

  @Test func exactNames() {
    #expect(parse("!Counterspell") == .cardName("Counterspell", exact: true))
    #expect(parse(#"!"Lightning Bolt""#) == .cardName("Lightning Bolt", exact: true))
    #expect(parse(#"-!"Lightning Bolt""#) == .not(.cardName("Lightning Bolt", exact: true)))
  }

  @Test func quotedOrIsAName() {
    #expect(parse(#"t:elf "or" t:goblin"#) == .and(.and(.type("elf"), .cardName("or")), .type("goblin")))
  }

  @Test func hyphenInsideWordIsNotNegation() {
    #expect(parse("o:mana-value") == .oracleContains("mana-value"))
    #expect(parse("prefer:usd-low") == .prefer(.usdLow))
  }

  @Test func unicodeOperators() {
    #expect(parse("usd≥5") == .price(.usd, .including, "5"))
    #expect(parse("mv≤2") == .stats(.cmc, .atMost, "2"))
  }

  @Test func operators() {
    #expect(parse("pow>=3") == .stats(.power, .including, "3"))
    #expect(parse("pow<=3") == .stats(.power, .atMost, "3"))
    #expect(parse("pow>3") == .stats(.power, .greaterThan, "3"))
    #expect(parse("pow<3") == .stats(.power, .lessThan, "3"))
    #expect(parse("pow!=3") == .stats(.power, .not, "3"))
    #expect(parse("pow=3") == .stats(.power, .exactly, "3"))
    #expect(parse("pow:3") == .stats(.power, .exactly, "3"))
    #expect(parse("pow>tou") == .stats(.power, .greaterThan, "tou"))
  }
}

// MARK: - Failure modes

@Suite struct FailureTests {
  @Test(arguments: ["", "   ", "(t:elf", "t:elf)", "()", "t:elf or", "or t:elf", "t:elf or or t:goblin", #"o:"unterminated"#, "o:/unterminated"])
  func invalidQueriesReturnNil(_ query: String) {
    #expect(parse(query) == nil)
  }

  @Test func unrecognizedKeysFailInStrictMode() {
    #expect(parse("foo:bar") == nil)
    #expect(parse("t:elf foo:bar") == nil)
    #expect(parse("c:m") == nil) // multicolor isn't representable
  }

  @Test func unrecognizedKeysAreKeptVerbatimInLenientMode() {
    #expect(parse("foo:bar", lenient: true) == .direct(query: "foo:bar"))
    #expect(parse(#"t:elf foo:"a b""#, lenient: true) == .and(.type("elf"), .direct(query: #"foo:"a b""#)))
  }
}

// MARK: - Term mapping

@Suite struct TermTests {
  @Test func colors() {
    #expect(parse("c:wu") == .colors(.color, [.w, .u], .including))
    #expect(parse("c=wu") == .colors(.color, [.w, .u], .exactly))
    #expect(parse("c:c") == .colors(.color, [.c], .exactly))
    #expect(parse("c:azorius") == .colors(.color, [.w, .u], .including))
    #expect(parse("id:wu") == .colors(.identity, [.w, .u], .atMost))
    #expect(parse("commander:wu") == .colors(.identity, [.w, .u], .atMost))
    #expect(parse("c:2") == .colorCount(.color, 2, .exactly))
    #expect(parse("id>=3") == .colorCount(.identity, 3, .including))
  }

  @Test func keysAreCaseInsensitive() {
    #expect(parse("T:Elf") == .type("Elf"))
  }

  @Test(arguments: [
    ("t:elf", ScryfallSearchToken.type("elf")),
    ("o:flying", .oracleContains("flying")),
    ("name:bolt", .cardName("bolt")),
    ("m:{2}{R}", .manaCost("{2}{R}", .including)),
    ("mana={R}{R}", .manaCost("{R}{R}", .exactly)),
    ("mv=3", .stats(.cmc, .exactly, "3")),
    ("cmc>2", .stats(.cmc, .greaterThan, "2")),
    ("loy>=4", .stats(.loyalty, .including, "4")),
    ("usd>=5", .price(.usd, .including, "5")),
    ("eur<1", .price(.eur, .lessThan, "1")),
    ("cn=5", .collectorNumber(.exactly, "5")),
    ("number>100", .collectorNumber(.greaterThan, "100")),
    ("year>=2020", .year(.including, "2020")),
    ("artists>1", .artists(.greaterThan, "1")),
    ("devotion>={u}{u}", .devotion(.including, "{u}{u}")),
    ("is:commander", .criterion("commander")),
    ("not:reprint", .not(.criterion("reprint"))),
    ("r:m", .rarity(.mythic, .exactly)),
    ("r>=rare", .rarity(.rare, .including)),
    ("s:dom", .sets(["dom"])),
    ("e:dom,war", .sets(["dom", "war"])),
    ("b:ktk", .blocks(["ktk"])),
    ("st:masters", .setType("masters")),
    ("in:lea", .in("lea")),
    ("in:collection", .criterion("owned")),
    ("kw:flying", .keyword("flying")),
    ("a:\"rebecca guay\"", .artist("rebecca guay")),
    ("wm:orzhov", .watermark("orzhov")),
    ("border:black", .border(.black)),
    ("ft:dragon", .flavorText("dragon")),
    ("lore:urza", .lore("urza")),
    ("include:extras", .include("extras")),
    ("unique:prints", .unique("prints")),
    ("f:modern", .legal(.legal, "modern")),
    ("legal:modern", .legal(.legal, "modern")),
    ("banned:legacy", .legal(.banned, "legacy")),
    ("restricted:vintage", .legal(.restricted, "vintage")),
    ("lang:ja", .language(.language(.japanese))),
    ("lang:any", .language(.any)),
    ("new:art", .new(.art)),
    ("cheapest:usd", .cheapest(.usd)),
    ("cube:vintage", .cube("vintage")),
    ("frame:1993", .frame(.classic1993)),
    ("stamp:acorn", .stamp(.acorn)),
    ("game:arena", .game(.arena)),
    ("prefer:oldest", .prefer(.oldest)),
    ("art:squirrel", .art("squirrel")),
    ("atag:squirrel", .art("squirrel")),
    ("function:removal", .function("removal")),
    ("otag:removal", .function("removal")),
    ("owned>=2", .owned(2, .including)),
  ])
  func term(_ query: String, _ expected: ScryfallSearchToken) {
    #expect(parse(query) == expected)
  }
}

// MARK: - Serialization

@Suite struct SerializationTests {
  @Test func orInsideAndIsParenthesized() {
    let token: ScryfallSearchToken = .and(.type("legendary"), .or(.type("goblin"), .type("elf")))
    #expect(token.queryString == "type:legendary (type:goblin OR type:elf)")
    let left: ScryfallSearchToken = .and(.or(.type("goblin"), .type("elf")), .type("legendary"))
    #expect(left.queryString == "(type:goblin OR type:elf) type:legendary")
  }

  @Test func andInsideOrIsNotParenthesized() {
    let token: ScryfallSearchToken = .or(.and(.type("legendary"), .type("goblin")), .type("elf"))
    #expect(token.queryString == "type:legendary type:goblin OR type:elf")
  }

  @Test func compoundNegationIsParenthesized() {
    #expect(ScryfallSearchToken.not(.and(.type("a"), .type("b"))).queryString == "-(type:a type:b)")
    #expect(ScryfallSearchToken.not(.or(.type("a"), .type("b"))).queryString == "-(type:a OR type:b)")
    #expect(ScryfallSearchToken.not(.type("a")).queryString == "-type:a")
    #expect(ScryfallSearchToken.not(.criterion("reprint")).queryString == "not:reprint")
    #expect(ScryfallSearchToken.not(.not(.type("a"))).queryString == "type:a")
  }

  @Test func directQueriesWithOrAreParenthesizedInsideAnd() {
    let token: ScryfallSearchToken = .and(.type("elf"), .direct(query: "o:a or o:b"))
    #expect(token.queryString == "type:elf (o:a or o:b)")
    let plain: ScryfallSearchToken = .and(.type("elf"), .direct(query: "o:orc"))
    #expect(plain.queryString == "type:elf o:orc")
  }

  @Test func namesAreQuotedWhenNeeded() {
    #expect(ScryfallSearchToken.cardName("Lightning Bolt", exact: true).queryString == #"!"Lightning Bolt""#)
    #expect(ScryfallSearchToken.cardName("Counterspell", exact: true).queryString == "!Counterspell")
    #expect(ScryfallSearchToken.cardName("bolt").queryString == "bolt")
    #expect(ScryfallSearchToken.cardName("or").queryString == #""or""#)
    #expect(ScryfallSearchToken.cardName("Protection:").queryString == #""Protection:""#)
    #expect(ScryfallSearchToken.cardName("-x").queryString == #""-x""#)
  }

  @Test func valuesWithQuotesUseTheOtherQuoteStyle() {
    #expect(ScryfallSearchToken.oracleContains(#"named "x""#).queryString == #"o:'named "x"'"#)
    #expect(ScryfallSearchToken.oracleContains("don't stop").queryString == #"o:"don't stop""#)
  }

  @Test func regexIsNotQuoted() {
    #expect(ScryfallSearchToken.oracleContains("/draw a card/").queryString == "o:/draw a card/")
  }

  @Test func priceUsesAsciiOperators() {
    #expect(ScryfallSearchToken.price(.usd, .including, "5").queryString == "usd>=5")
    #expect(ScryfallSearchToken.price(.eur, .atMost, "5").queryString == "eur<=5")
  }
}

// MARK: - Round trip

/// Queries that exercise every part of the grammar. Shared with the live tests.
let roundTripCorpus: [String] = [
  "t:legendary t:goblin or t:elf",
  "t:legendary (t:goblin or t:elf)",
  "(t:elf t:warrior) or (t:goblin t:shaman)",
  "((t:elf or t:goblin) c:g) or t:dragon",
  "-t:creature t:artifact",
  "-(t:creature t:artifact)",
  "-(t:goblin or t:elf) c:r",
  "-t:goblin or t:elf",
  "t:goblin or t:elf or t:human",
  "t:elf and t:warrior",
  #"o:"draw a card" c:u"#,
  "o:'enters the battlefield' t:creature",
  "o:/^{T}: add/ t:land -t:basic",
  #"!"Lightning Bolt""#,
  "urza's tower",
  "lightning bolt",
  "c:wu",
  "c=wu t:creature",
  "c:c t:artifact",
  "c:2 t:creature mv=2",
  "id<=wu is:commander",
  "commander:wubrg",
  "m:{2}{R} t:instant",
  "mana={R}{R}",
  "pow>=5 tou<=2",
  "pow>tou t:creature",
  "loy>=5",
  "mv=3 or mv=4",
  "usd>=5 usd<6",
  "usd≥5 r:m",
  "cn=5 s:dom",
  "year>=2024 t:dragon",
  "artists>1",
  "devotion>={u}{u}{u}",
  "not:reprint s:dom",
  "-is:reprint s:dom",
  "r:m s:war",
  "r>=rare s:dom",
  "s:dom,war",
  "b:ktk t:dragon",
  "st:masters t:elf",
  "in:lea t:creature",
  "kw:flying c:w mv<=2",
  #"a:"rebecca guay""#,
  "wm:orzhov",
  "border:white t:creature",
  "ft:dragon",
  "lore:urza",
  "f:modern t:elf",
  "banned:legacy",
  "restricted:vintage",
  "lang:ja s:war",
  "new:art s:war",
  "cheapest:usd t:goblin",
  "cube:vintage t:planeswalker",
  "frame:1993 t:dragon",
  "stamp:acorn",
  "game:arena s:dom",
  "function:removal c:w",
  "art:squirrel",
  "t:legend t:walker",
  "unique:prints !Counterspell",
  "include:extras t:scheme",
]

@Suite struct RoundTripTests {
  /// parse → serialize → parse yields the same tree, so serializing never
  /// changes the meaning of a parsed query.
  @Test(arguments: roundTripCorpus)
  func parseSerializeParseIsStable(_ query: String) throws {
    let token = try #require(parse(query), "failed to parse \(query)")
    let serialized = token.queryString
    let reparsed = try #require(parse(serialized), "failed to reparse \(serialized)")
    #expect(reparsed == token, "\(query) → \(serialized)")
    // And serialization is a fixed point after one pass.
    #expect(reparsed.queryString == serialized)
  }

  /// Every token shape the app builds programmatically must serialize to
  /// something the tokenizer reads back to the same meaning.
  @Test(arguments: constructedTokens)
  func serializeParseMatchesConstructedTokens(_ token: ScryfallSearchToken) throws {
    let serialized = token.queryString
    let reparsed = try #require(parse(serialized), "failed to parse \(serialized)")
    #expect(reparsed.normalized == token.normalized, "\(serialized)")
  }
}

let constructedTokens: [ScryfallSearchToken] = [
  .and(.type("legendary"), .or(.type("goblin"), .type("elf"))),
  .and(.or(.type("goblin"), .type("elf")), .or(.colors(.color, [.r], .including), .colors(.color, [.g], .including))),
  .and(.type("a"), .and(.type("b"), .type("c"))), // right-associated AND
  .or(.type("a"), .or(.type("b"), .type("c"))), // right-associated OR
  .not(.and(.type("creature"), .type("artifact"))),
  .not(.or(.type("goblin"), .type("elf"))),
  .not(.criterion("reprint")),
  .parentheses(.or(.type("a"), .type("b"))),
  .and(.parentheses(.type("a")), .type("b")),
  .cardName("Lightning Bolt", exact: true),
  .cardName("or"),
  .cardName("Protection:"),
  .oracleContains("draw a card"),
  .oracleContains(#"named "x""#),
  .oracleContains("/draw a card/"),
  .type("legendary creature"),
  .colors(.identity, [.w, .u, .b], .atMost),
  .colors(.color, [.r, .g], .exactly),
  .colors(.color, [.w], .not),
  .colorCount(.color, 2, .greaterThan),
  .manaCost("{2}{R}", .including),
  .stats(.toughness, .lessThan, "3"),
  .price(.tix, .greaterThan, "1"),
  .legal(.banned, "modern"),
  .sets(["dom", "war"]),
  .blocks(["ktk"]),
  .in("lea"),
  .rarity(.uncommon, .atMost),
  .keyword("first strike"),
  .criterion("commander"),
  .year(.lessThan, "2000"),
  .border(.borderless),
  .artist("Rebecca Guay"),
  .include("extras"),
  .flavorText("for the horde"),
  .lore("urza"),
  .unique("art"),
  .language(.language(.japanese)),
  .language(.any),
  .watermark("set"),
  .owned(1, .including),
  .new(.art),
  .cheapest(.eur),
  .artists(.greaterThan, "1"),
  .devotion(.including, "{G}{G}"),
  .collectorNumber(.exactly, "1a"),
  .setType("masters"),
  .cube("vintage"),
  .frame(.future),
  .stamp(.oval),
  .game(.paper),
  .prefer(.usdLow),
  .art("squirrel"),
  .function("removal"),
]

extension ScryfallSearchToken {
  /// Strips `.parentheses`, cancels double negation, and left-associates
  /// AND/OR chains, so trees with the same meaning compare equal.
  var normalized: ScryfallSearchToken {
    switch self {
    case .parentheses(let inner):
      return inner.normalized
    case .not(.not(let inner)):
      return inner.normalized
    case .not(let inner):
      return .not(inner.normalized)
    case .and:
      return Self.chain(operands(and: true).map(\.normalized), and: true)
    case .or:
      return Self.chain(operands(and: false).map(\.normalized), and: false)
    default:
      return self
    }
  }

  /// The operands of an AND (or OR) chain, looking through parentheses.
  private func operands(and: Bool) -> [ScryfallSearchToken] {
    switch (self, and) {
    case (.parentheses(let inner), _):
      return inner.operands(and: and)
    case (.and(let l, let r), true), (.or(let l, let r), false):
      return l.operands(and: and) + r.operands(and: and)
    default:
      return [self]
    }
  }

  private static func chain(_ tokens: [ScryfallSearchToken], and: Bool) -> ScryfallSearchToken {
    // Operands may themselves have normalized into the same operator.
    let flat = tokens.flatMap { $0.operands(and: and) }
    return flat.dropFirst().reduce(flat[0]) { and ? .and($0, $1) : .or($0, $1) }
  }
}
