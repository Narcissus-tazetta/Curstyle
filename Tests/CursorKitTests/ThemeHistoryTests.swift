import CoreGraphics
import Foundation
import XCTest

@testable import CursorKit

final class ThemeHistoryTests: XCTestCase {
    func testUndoSurvivesReloadAndNewEditsBranchFromRestoredState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try! FileManager.default.removeItem(at: root) }
        let library = try ThemeLibrary(root: root)
        let context = CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let rep = CursorRep(
            size: CGSize(width: 16, height: 16), hotspot: .zero,
            frameCount: 1, frameDuration: 0, images: [context.makeImage()!])
        let original = CursorTheme(name: "Original", cursors: ["arrow": rep])
        var entry = try library.add(original)
        var edited = original
        edited.cursors["arrow"]!.hotspot = CGPoint(x: 3, y: 4)
        entry = try library.update(entry, with: edited)
        edited = try edited.scalingSize(by: 2)
        entry = try library.update(entry, with: edited)
        try Data().write(to: entry.directory.appendingPathComponent(".undo/.DS_Store"))
        let reopened = try ThemeLibrary(root: root)
        entry = try XCTUnwrap(reopened.load().entries.first)
        XCTAssertEqual(entry.undoCount, 2)
        entry = try reopened.undo(entry)
        XCTAssertEqual(entry.theme.cursors["arrow"]!.size.width, 16)
        XCTAssertEqual(entry.theme.cursors["arrow"]!.hotspot, CGPoint(x: 3, y: 4))
        var invalid = entry.theme
        invalid.cursors = [:]
        XCTAssertThrowsError(try reopened.update(entry, with: invalid))
        XCTAssertEqual(reopened.load().entries.first!.undoCount, 1)
        entry = try reopened.undo(entry)
        XCTAssertEqual(entry.undoCount, 0)
        XCTAssertEqual(entry.theme.fingerprint, original.fingerprint)
        entry = try reopened.update(entry, with: edited)
        XCTAssertEqual(entry.undoCount, 1)
        entry = try reopened.undo(entry)
        XCTAssertEqual(entry.theme.fingerprint, original.fingerprint)
        XCTAssertTrue(reopened.load().errors.isEmpty)
    }
}
