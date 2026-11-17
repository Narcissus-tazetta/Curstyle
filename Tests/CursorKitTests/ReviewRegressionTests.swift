import CoreGraphics
import Foundation
import XCTest
@testable import CursorKit

final class ReviewRegressionTests: XCTestCase {
    func testInvalidLibraryThemeIsReportedInsteadOfRendered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try! FileManager.default.removeItem(at: root) }
        let library = try ThemeLibrary(root: root)
        let directory = root.appendingPathComponent("broken")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"{"name":"Broken","cursors":{"arrow":{"size":[0,16],"hotspot":[0,0],"images":[]}}}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("theme.json"))
        let loaded = library.load()
        XCTAssertTrue(loaded.entries.isEmpty)
        XCTAssertEqual(loaded.errors.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testJournalSavesHaveDistinctTokensEvenWithIdenticalDates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try! FileManager.default.removeItem(at: root) }
        let store = try SnapshotStore(root: root)
        try store.saveJournal(.clean)
        let first = try store.loadJournal()
        try store.saveJournal(.clean)
        var second = try store.loadJournal()
        second.updatedAt = first.updatedAt
        XCTAssertNotEqual(first.changeToken, second.changeToken)
        XCTAssertNotNil(first.revision)
        XCTAssertNotNil(second.revision)
    }

    func testShortAnimationDurationDoesNotOverflowFrameIndex() {
        let rep = CursorRep(size: CGSize(width: 16, height: 16), hotspot: .zero,
                            frameCount: 2, frameDuration: 1e-20, images: [])
        XCTAssertTrue((0..<2).contains(rep.animationFrameIndex(at: 800_000_000)))
        var regular = rep
        regular.frameDuration = 0.25
        XCTAssertEqual(regular.animationFrameIndex(at: 0.1), 0)
        XCTAssertEqual(regular.animationFrameIndex(at: 0.3), 1)
        XCTAssertEqual(regular.animationFrameIndex(at: 0.6), 0)
    }

    func testLegacyJournalWithoutRevisionStillLoads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try! FileManager.default.removeItem(at: root) }
        let store = try SnapshotStore(root: root)
        let json = #"{"status":"clean","intended":{},"updatedAt":"2026-11-17T00:00:00Z"}"#
        try Data(json.utf8).write(to: root.appendingPathComponent("journal.json"))
        let journal = try store.loadJournal()
        XCTAssertNil(journal.revision)
        XCTAssertEqual(journal.status, .clean)
        XCTAssertEqual(journal.changeToken, try store.loadJournal().changeToken)
    }
}
