//
//  Option.swift
//  ScryfallSearchKit
//

import Foundation

/// A titled value, used for pickers and suggestions.
public struct Option: Equatable, Hashable, ExpressibleByStringLiteral, Sendable {
  public let title: String
  public let value: String
  public let description: String?
  public typealias StringLiteralType = String

  public init(_ title: String, value: String? = nil, description: String? = nil) {
    self.title = title
    self.value = value ?? title
    self.description = description
  }

  public init(stringLiteral value: String) {
    self.init(value)
  }
}
