import Foundation
public enum SupportedLanguage: String, CaseIterable {
    case system, en, he, fr, nl, de, es, it, pt, ru, ar, ja, zhHans, zhHant
    public var isRTL: Bool { self == .he || self == .ar }

    /// A valid BCP-47 identifier for this case — needed because `zhHans`/`zhHant` (valid Swift
    /// case names) aren't valid Locale identifiers on their own; every other case already is one.
    public var localeIdentifier: String {
        switch self {
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        default: return rawValue
        }
    }
}
public let requiredLocalizationKeys = ["app.name","app.tagline","tab.home","tab.items","tab.calendar","tab.insights","tab.settings","add.anything","add.justTellMe","aiConsent.title","empty.allClear","settings.language"]
