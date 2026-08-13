import Foundation
public enum SupportedLanguage: String, CaseIterable { case system, en, he, fr, nl, de, es, it, pt, ru, ar, ja, zhHans, zhHant; public var isRTL: Bool { self == .he || self == .ar } }
public let requiredLocalizationKeys = ["app.name","app.tagline","tab.home","tab.items","tab.calendar","tab.insights","tab.settings","add.anything","add.justTellMe","privacy.aiProcessing","empty.allClear","settings.language"]
