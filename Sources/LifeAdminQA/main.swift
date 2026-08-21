import Foundation
import LifeAdminCore

/// This used to print a fixed set of "PASS" lines regardless of anything actually being true —
/// "Accessibility: PASS labels audited in SwiftUI source", "Notifications: PASS reminder dates
/// validated" — none of which this file ever checked. That's worse than no report at all: it
/// looks like automated verification while verifying nothing. The one thing genuinely checkable
/// from a plain Foundation script — that every locale's Localizable.strings has the exact same
/// keys as every other, with no duplicates, and covers every key the app assumes exists — is
/// checked for real here, and this exits non-zero on failure so CI actually catches a regression
/// instead of relying on someone re-running the same manual diff by hand each time.

private func parseStringsFile(at url: URL) -> (keys: [String], duplicates: Set<String>)? {
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    let regex = try! NSRegularExpression(pattern: #"^"([^"]+)"\s*="#)
    var keys: [String] = []
    var seen = Set<String>()
    var duplicates = Set<String>()
    for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
        let lineString = String(line)
        let range = NSRange(lineString.startIndex..., in: lineString)
        guard let match = regex.firstMatch(in: lineString, range: range),
              let keyRange = Range(match.range(at: 1), in: lineString) else { continue }
        let key = String(lineString[keyRange])
        if seen.contains(key) { duplicates.insert(key) }
        seen.insert(key)
        keys.append(key)
    }
    return (keys, duplicates)
}

// Sources/LifeAdminQA/main.swift -> Sources/LifeAdminQA -> Sources -> repo root
let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resourcesDir = packageRoot.appendingPathComponent("LifeAdminApp/Resources")

var failures: [String] = []
var localeKeySets: [String: Set<String>] = [:]

guard let lprojDirs = try? FileManager.default.contentsOfDirectory(at: resourcesDir, includingPropertiesForKeys: nil) else {
    print("Life Admin QA Report")
    print("Localization: FAIL could not read \(resourcesDir.path)")
    exit(1)
}

for dir in lprojDirs.filter({ $0.pathExtension == "lproj" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let locale = dir.deletingPathExtension().lastPathComponent
    let file = dir.appendingPathComponent("Localizable.strings")
    guard let parsed = parseStringsFile(at: file), parsed.keys.isEmpty == false else {
        failures.append("\(locale): couldn't read or empty Localizable.strings")
        continue
    }
    if parsed.duplicates.isEmpty == false {
        failures.append("\(locale): duplicate keys — \(parsed.duplicates.sorted().joined(separator: ", "))")
    }
    localeKeySets[locale] = Set(parsed.keys)
}

if let referenceKeys = localeKeySets["en"] {
    for (locale, keys) in localeKeySets.sorted(by: { $0.key < $1.key }) where locale != "en" {
        let missing = referenceKeys.subtracting(keys)
        let extra = keys.subtracting(referenceKeys)
        if missing.isEmpty == false {
            failures.append("\(locale): missing \(missing.count) key(s) present in en — \(missing.sorted().joined(separator: ", "))")
        }
        if extra.isEmpty == false {
            failures.append("\(locale): has \(extra.count) key(s) not present in en — \(extra.sorted().joined(separator: ", "))")
        }
    }
    let missingRequired = requiredLocalizationKeys.filter { referenceKeys.contains($0) == false }
    if missingRequired.isEmpty == false {
        failures.append("en.lproj is missing key(s) listed in requiredLocalizationKeys — \(missingRequired.joined(separator: ", "))")
    }
} else {
    failures.append("en.lproj not found — nothing to use as the reference key set")
}

print("Life Admin QA Report")
print("Locales checked: \(localeKeySets.keys.sorted().joined(separator: ", "))")
if failures.isEmpty {
    print("Localization: PASS — \(localeKeySets.count) locales, \(localeKeySets["en"]?.count ?? 0) keys each, key-for-key identical, no duplicates")
} else {
    print("Localization: FAIL")
    for failure in failures { print("  - \(failure)") }
}
print("Note: this tool only checks Localizable.strings consistency. Run `swift test` for unit tests and `scripts/security_scan.sh` for the secret scan.")
print("Final Status: \(failures.isEmpty ? "PASS" : "FAIL")")
exit(failures.isEmpty ? 0 : 1)
