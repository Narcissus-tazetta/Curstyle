import Foundation
import XCTest

@testable import CursorKit

final class LocalizationTests: XCTestCase {
    func testDefaultLanguageUsesJapaneseOnlyForJapanesePrimaryLanguage() {
        for tag in ["ja", "ja-JP", "ja_JP"] {
            XCTAssertEqual(L10n.resolveLanguage(override: nil, preferredLanguages: [tag, "en"]), "ja")
        }
        for languages in [[], ["en-US"], ["fr-FR", "ja"], ["zh-Hans"]] {
            XCTAssertEqual(L10n.resolveLanguage(override: nil, preferredLanguages: languages), "en")
        }
    }

    func testExplicitLanguageOverridesSystemLanguage() {
        XCTAssertEqual(L10n.resolveLanguage(override: "en", preferredLanguages: ["ja-JP"]), "en")
        XCTAssertEqual(L10n.resolveLanguage(override: "ja", preferredLanguages: ["en-US"]), "ja")
        XCTAssertEqual(L10n.resolveLanguage(override: "", preferredLanguages: ["ja-JP"]), "ja")
    }

    func testTranslationPreservesUserContentAndReordersArguments() {
        XCTAssertEqual(L10n.translated("設定", arguments: [], language: "en"), "Settings")
        XCTAssertEqual(L10n.translated("設定", arguments: [], language: "ja"), "設定")
        XCTAssertEqual(
            L10n.translated("{0} のコマ {1} を読めない", arguments: ["User {1} theme", "7"], language: "en"),
            "Could not read frame 7 in User {1} theme")
        XCTAssertEqual(
            L10n.translated("{0} を追加しました", arguments: ["日本語のテーマ"], language: "en"),
            "Added 日本語のテーマ")
    }

    func testCatalogsHaveMatchingKeysPlaceholdersAndFormatSpecifiers() throws {
        func catalog(_ language: String) throws -> [String: String] {
            let bundle = Bundle(url: L10n.resourceBundleURL)!
            let url = bundle.url(
                forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language)!
            return try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
                as! [String: String]
        }
        let english = try catalog("en")
        let japanese = try catalog("ja")
        XCTAssertGreaterThan(english.count, 370)
        XCTAssertEqual(Set(english.keys), Set(japanese.keys))
        let expression = try NSRegularExpression(pattern: #"\{\d+\}|%[-+0-9.]*[dfgs@]"#)
        func markers(_ value: String) -> [String] {
            expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .map { (value as NSString).substring(with: $0.range) }.sorted()
        }
        for (key, translation) in english {
            XCTAssertEqual(markers(translation), markers(japanese[key]!), key)
            XCTAssertFalse(translation.isEmpty, key)
            let argumentCount = (0..<20).prefix { key.contains("{\($0)}") }.count
            let arguments = (0..<argumentCount).map { "argument \($0)" }
            XCTAssertEqual(
                L10n.translated(key, arguments: arguments, language: "ja"),
                arguments.enumerated().reduce(japanese[key]!) {
                    $0.replacingOccurrences(of: "{\($1.offset)}", with: $1.element)
                })
        }
    }
}
