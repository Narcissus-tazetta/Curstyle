import Foundation

public enum L10n {
    public static let preferenceKey = "displayLanguage"
    // The app and its separately launched helper must share the same language preference.
    // Foundation documents UserDefaults as thread-safe, but its SDK type is not Sendable.
    nonisolated(unsafe) public static let preferences: UserDefaults =
        Bundle.main.bundleIdentifier == "io.github.narcissus-tazetta.curstyle"
        ? .standard : UserDefaults(suiteName: "io.github.narcissus-tazetta.curstyle")!

    public static var language: String {
        resolveLanguage(
            override: preferences.string(forKey: preferenceKey), preferredLanguages: Locale.preferredLanguages)
    }

    public static func resolveLanguage(override: String?, preferredLanguages: [String]) -> String {
        if let override, ["en", "ja"].contains(override) { return override }
        let first = preferredLanguages.first ?? "en"
        return Locale(identifier: first).language.languageCode?.identifier == "ja" ? "ja" : "en"
    }

    public static func setLanguage(_ language: String) {
        preferences.set(language, forKey: preferenceKey)
        // AppKit's standard menus and panels resolve their language at process startup.
        preferences.set([language], forKey: "AppleLanguages")
    }

    public static var resourceBundleURL: URL { Bundle.module.bundleURL }

    private static let bundles: [String: Bundle] = Dictionary(
        uniqueKeysWithValues: ["en", "ja"].map {
            ($0, Bundle(url: Bundle.module.url(forResource: $0, withExtension: "lproj")!)!)
        })
    private static let placeholder = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)

    public static func text(_ key: String, _ arguments: String...) -> String {
        translated(key, arguments: arguments, language: language)
    }

    static func translated(_ key: String, arguments: [String], language: String) -> String {
        let template = bundles[language]!.localizedString(forKey: key, value: nil, table: nil)
        let result = NSMutableString(string: template)
        for match in placeholder.matches(in: template, range: NSRange(location: 0, length: result.length)).reversed() {
            let index = Int((template as NSString).substring(with: match.range(at: 1)))!
            result.replaceCharacters(in: match.range, with: arguments[index])
        }
        return result as String
    }
}
