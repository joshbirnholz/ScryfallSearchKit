//
//  ScryfallSecurityStamp.swift
//  ScryfallSearchKit
//

import Foundation

/// The security stamp printed on a card (`stamp:` in Scryfall syntax).
public enum ScryfallSecurityStamp: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
  case oval
  case triangle
  case acorn
  case arena
  case heart

  public var descriptiveString: String {
    switch self {
    case .oval: "ovular"
    case .triangle: "triangular"
    case .acorn: "acorn/funny"
    case .arena: "Arena"
    case .heart: "heart"
    }
  }
}
