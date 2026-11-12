//
//  ScryfallLanguage.swift
//  ScryfallSearchKit
//

import Foundation

/// A language Scryfall prints cards in (`lang:` in Scryfall syntax).
public enum ScryfallLanguage: RawRepresentable, Codable, Equatable, Hashable, CaseIterable, Sendable {
  case english
  case spanish
  case french
  case german
  case italian
  case portuguese
  case japanese
  case korean
  case russian
  case simplifiedChinese
  case traditionalChinese
  case hebrew
  case latin
  case ancientGreek
  case arabic
  case sanskrit
  case phyrexian
  case quenya
  case dwarvish
  case klingon
  case unknown(String)
  
  private static let orderedCases: [ScryfallLanguage] = [
      .english, .spanish, .french, .german, .italian, .portuguese,
      .japanese, .korean, .russian, .simplifiedChinese, .traditionalChinese,
      .hebrew, .latin, .ancientGreek, .arabic, .sanskrit, .phyrexian,
      .quenya, .dwarvish, .klingon
  ]

  public static var allCases: [ScryfallLanguage] { orderedCases }

  private static let indexByCase: [ScryfallLanguage: Int] =
      Dictionary(uniqueKeysWithValues: orderedCases.enumerated().map { ($0.offset, $0.element) }.map { ($1, $0) })

  public var value: Int { Self.indexByCase[self] ?? Self.orderedCases.count }
  
  public var rawValue: String {
    abbreviation
  }
  
  public init(rawValue: String) {
    let lower = rawValue.lowercased()
    for lang in Self.allCases {
      if lower == lang.abbreviation {
        self = lang
        return
      }
    }
    self = .unknown(rawValue)
  }
  
  public var abbreviation: String {
    switch self {
    case .english: "en"
    case .spanish: "es"
    case .french: "fr"
    case .german: "de"
    case .italian: "it"
    case .portuguese: "pt"
    case .japanese: "ja"
    case .korean: "ko"
    case .russian: "ru"
    case .simplifiedChinese: "zhs"
    case .traditionalChinese: "zht"
    case .hebrew: "he"
    case .latin: "la"
    case .ancientGreek: "grc"
    case .arabic: "ar"
    case .sanskrit: "sa"
    case .phyrexian: "ph"
    case .quenya: "qya"
    case .dwarvish: "dw"
    case .klingon: "kl"
    case .unknown(let abbr): abbr.lowercased()
    }
  }
  
  public var name: String {
    switch self {
    case .english:
      return "English"
    case .spanish:
      return "Spanish"
    case .french:
      return "French"
    case .german:
      return "German"
    case .italian:
      return "Italian"
    case .portuguese:
      return "Portuguese"
    case .japanese:
      return "Japanese"
    case .korean:
      return "Korean"
    case .russian:
      return "Russian"
    case .simplifiedChinese:
      return "Simplified Chinese"
    case .traditionalChinese:
      return "Traditional Chinese"
    case .hebrew:
      return "Hebrew"
    case .latin:
      return "Latin"
    case .ancientGreek:
      return "Ancient Greek"
    case .arabic:
      return "Arabic"
    case .sanskrit:
      return "Sanskrit"
    case .phyrexian:
      return "Phyrexian"
    case .quenya:
      return "Quenya"
    case .dwarvish:
      return "Dwarvish"
    case .klingon:
      return "Klingon"
    case .unknown(let abbr):
      return abbr.uppercased()
    }
  }
  
  public var displayAbbreviation: String {
    switch self {
    case .simplifiedChinese: return "汉语"
    case .traditionalChinese: return "漢語"
    default: return abbreviation.uppercased()
    }
  }
  
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
  
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    self.init(rawValue: value)
  }
  
  public static func ==(lhs: ScryfallLanguage, rhs: ScryfallLanguage) -> Bool {
    // `rawValue` is the lowercased abbreviation for every case, including `.unknown`.
    lhs.rawValue == rhs.rawValue
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(rawValue)
  }
}
