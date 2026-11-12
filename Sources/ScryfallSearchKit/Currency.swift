//
//  Currency.swift
//  ScryfallSearchKit
//

import Foundation

/// A currency Scryfall reports prices in.
public enum Currency: String, CaseIterable, Equatable, Codable, Sendable {
  case usd
  case eur
  case tix

  public var humanReadable: String {
    switch self {
    case .usd: return "USD"
    case .eur: return "Euros"
    case .tix: return "MTGO Tickets"
    }
  }

  public var symbol: String {
    switch self {
    case .usd: return "$"
    case .eur: return "€"
    case .tix: return "TIX: "
    }
  }
}
