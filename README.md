# ScryfallSearchKit

A model and parser for [Scryfall search syntax](https://scryfall.com/docs/syntax), extracted from Spellbook.

- `ScryfallSearchToken` — an indirect enum describing a query (`.type`, `.colors`, `.and`, `.or`, `.not`, …). `queryString` serializes it back to Scryfall syntax; `humanReadableDescription` describes it in English.
- `ScryfallTokenizer` — parses a query string into a token tree.

```swift
let token = ScryfallTokenizer().scryfallToken(for: "t:legendary t:goblin or t:elf")
// .or(.and(.type("legendary"), .type("goblin")), .type("elf"))
token?.queryString // "type:legendary type:goblin OR type:elf"
```

## Grammar

Matches Scryfall's precedence (checked against the live API): `-` binds tightest, then implicit AND (adjacency; the word `and` is ignored), then `or`. Parentheses group. Unbalanced parentheses, dangling operators and unterminated quotes or regexes return `nil`.

By default an unrecognized `key:value` term makes the parse return `nil`. Pass `ignoreUnrecognized: true` to keep such terms verbatim as `.direct(query:)`.

## Tests

```bash
swift test
```

Live tests check that `parse(q).queryString` returns the same number of cards from Scryfall as `q`. They hit the network and are rate-limited, so they're opt-in:

```bash
SCRYFALL_LIVE_TESTS=1 swift test --filter LiveScryfallTests
```

## Offline search

The package has no dependency on Scryfall's servers, so a token tree can be evaluated against a local copy of the card database:

- `token.matches(card) { term, card in … }` evaluates in memory. Your closure handles each leaf term (`.type`, `.stats`, …) and returns `nil` for unsupported ones, which makes the whole result `nil` so you can fall back to an online search instead of returning wrong results.
- `token.translated(with: myTranslator)` builds a storage query (an `NSPredicate`, SwiftData `Predicate`, SQL, …) from a `ScryfallSearchTokenTranslator`. The package handles AND/OR/NOT/parentheses; the translator only handles leaves.
- `token.directives` returns `unique:`, `include:` and `prefer:`, which change how results are returned rather than which cards match. Both evaluation paths skip them.

Parse in strict mode (the default) for offline search, so unknown syntax fails up front instead of becoming an opaque `.direct` query.
