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

    // SwiftPM's Bundle.module only looks next to the .app and at the absolute build path, so a distributed app
    // that was built elsewhere crashes at launch. Look where the app, the CLI inside it, and the copied helper keep it.
    public static let resourceBundleURL: URL = {
        let name = "Curstyle_CursorKit.bundle"
        let main = Bundle.main
        let candidates = [
            main.resourceURL,
            main.bundleURL,
            main.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true),
        ].compactMap { $0?.appendingPathComponent(name, isDirectory: true) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? Bundle.module.bundleURL
    }()

    private static let bundles: [String: Bundle] = {
        let resources = Bundle(url: resourceBundleURL)!
        return Dictionary(
            uniqueKeysWithValues: ["en", "ja"].map {
                ($0, Bundle(url: resources.url(forResource: $0, withExtension: "lproj")!)!)
            })
    }()
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
