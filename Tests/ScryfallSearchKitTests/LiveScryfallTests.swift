import Foundation
import Testing
@testable import ScryfallSearchKit

/// Checks against the live Scryfall API that serializing a parsed query
/// doesn't change its results: `q` and `parse(q).queryString` must return the
/// same number of cards.
///
/// These hit the network, so they only run when `SCRYFALL_LIVE_TESTS=1`:
///
///     SCRYFALL_LIVE_TESTS=1 swift test --filter LiveScryfallTests
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SCRYFALL_LIVE_TESTS"] == "1"))
struct LiveScryfallTests {
  /// Queries whose meaning is Spellbook-specific and that Scryfall rejects.
  private static let appOnly: Set<String> = []

  @Test(arguments: roundTripCorpus)
  func serializedQueryMatchesScryfallResults(_ query: String) async throws {
    let token = try #require(ScryfallTokenizer().scryfallToken(for: query))
    let serialized = token.queryString

    let original = try await ScryfallCount.totalCards(for: query)
    let roundTripped = serialized == query ? original : try await ScryfallCount.totalCards(for: serialized)

    #expect(original == roundTripped, "\(query) (\(original.map(String.init) ?? "error")) → \(serialized) (\(roundTripped.map(String.init) ?? "error"))")
    #expect(original != nil, "Scryfall rejected the original query \(query)")
  }

  /// The precedence the tokenizer assumes, checked directly against Scryfall.
  @Test func scryfallPrecedenceMatchesTokenizer() async throws {
    let implicit = try await ScryfallCount.totalCards(for: "t:legendary t:goblin or t:elf")
    let andFirst = try await ScryfallCount.totalCards(for: "(t:legendary t:goblin) or t:elf")
    let orFirst = try await ScryfallCount.totalCards(for: "t:legendary (t:goblin or t:elf)")
    #expect(implicit == andFirst)
    #expect(implicit != orFirst)

    let notImplicit = try await ScryfallCount.totalCards(for: "-t:goblin or t:elf")
    let notFirst = try await ScryfallCount.totalCards(for: "(-t:goblin) or t:elf")
    #expect(notImplicit == notFirst)
  }
}

enum ScryfallCount {
  private struct List: Decodable { let total_cards: Int? }
  private struct ErrorBody: Decodable { let code: String }

  /// The number of cards Scryfall returns, `0` for "no matches", or `nil` if
  /// Scryfall rejected the query.
  static func totalCards(for query: String) async throws -> Int? {
    // Scryfall rate-limits search, so pace requests and back off on 429.
    for attempt in 0..<6 {
      try await Task.sleep(for: .milliseconds(attempt == 0 ? 1_000 : 5_000 * attempt))
      if let result = try await fetch(query) { return result.count }
    }
    Issue.record("Scryfall kept rate-limiting \(query)")
    return nil
  }

  /// `nil` when rate-limited, otherwise the result (whose `count` is `nil` on a rejected query).
  private static func fetch(_ query: String) async throws -> (count: Int?, Void)? {

    var components = URLComponents(string: "https://api.scryfall.com/cards/search")!
    components.queryItems = [URLQueryItem(name: "q", value: query)]
    // URLComponents leaves "+" alone, which servers read as a space.
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

    var request = URLRequest(url: components.url!)
    request.setValue("ScryfallSearchKitTests/1.0", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    switch status {
    case 200:
      return (try JSONDecoder().decode(List.self, from: data).total_cards, ())
    case 429:
      return nil
    case 404 where (try? JSONDecoder().decode(ErrorBody.self, from: data))?.code == "not_found":
      return (0, ())
    default:
      return (nil, ())
    }
  }
}
