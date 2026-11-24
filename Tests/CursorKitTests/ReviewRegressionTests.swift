import AppKit
import CoreGraphics
import Foundation
import XCTest

@testable import CursorKit

final class ReviewRegressionTests: XCTestCase {
    @MainActor
    func testOverlayMatchesLowerResolutionAndKeepsAllCandidateRoles() throws {
        let rep = try makeCursor(red: 0.5)
        let lowResolution = try XCTUnwrap(rep.images.first)
        var multipleScales = rep
        multipleScales.images.append(
            try resampleStrip(lowResolution, frameCount: 1, to: CGSize(width: 4, height: 4)))
        let matcher = ShapeMatcher()
        matcher.add(name: "left", rep: multipleScales)
        matcher.add(name: "right", rep: rep)

        let cursor = NSCursor(image: NSImage(cgImage: lowResolution, size: rep.size), hotSpot: rep.hotspot)
        let names = matcher.names(for: cursor).names
        XCTAssertEqual(names, ["left", "right"])
        XCTAssertNotNil(ShapeMatcher.themedName(for: names, hashes: ["left": "shared", "right": "shared"]))
        XCTAssertNil(ShapeMatcher.themedName(for: names, hashes: ["left": "first", "right": "second"]))
        XCTAssertNil(ShapeMatcher.themedName(for: names, hashes: ["left": "only"]))
    }

    func testOverlayRequiresTheWholeCursorImageToFitAcrossDisplays() {
        let left = CGRect(x: 0, y: 0, width: 100, height: 100)
        let right = CGRect(x: 100, y: 0, width: 100, height: 100)
        let acrossSeam = CGRect(x: 90, y: 10, width: 20, height: 20)

        XCTAssertTrue(OverlayRenderer.isCovered(CGRect(x: 10, y: 10, width: 20, height: 20), by: [left]))
        XCTAssertTrue(OverlayRenderer.isCovered(acrossSeam, by: [left, right]))
        XCTAssertFalse(OverlayRenderer.isCovered(acrossSeam, by: [left]))
        XCTAssertFalse(OverlayRenderer.isCovered(acrossSeam, by: [left, right.offsetBy(dx: 4, dy: 0)]))
        XCTAssertFalse(OverlayRenderer.isCovered(acrossSeam, by: [left, right.offsetBy(dx: 0, dy: 20)]))
        XCTAssertFalse(OverlayRenderer.isCovered(acrossSeam, by: []))
    }

    func testTransparentFrameAtAnyResolutionBlocksRegistrationBeforeChangingState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try! FileManager.default.removeItem(at: root) }
        let store = try SnapshotStore(root: root)
        let backend = MemoryBackend()
        let arrow = try XCTUnwrap(CursorCatalog.targets(for: "arrow").first)
        let standard = try makeCursor(red: 0.5)
        backend.cursors[arrow] = standard

        let small = standard.images[0]
        let retinaContext = try XCTUnwrap(
            CGContext(
                data: nil, width: 4, height: 8, bitsPerComponent: 8, bytesPerRow: 16,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        retinaContext.draw(small, in: CGRect(x: 0, y: 4, width: 4, height: 4))
        let rep = CursorRep(
            size: standard.size, hotspot: .zero, frameCount: 2, frameDuration: 0.1,
            images: [try WindowsCursorImporter.stack([small, small]), try XCTUnwrap(retinaContext.makeImage())])
        let theme = CursorTheme(name: "Blank animation frame", cursors: ["arrow": rep])

        XCTAssertNoThrow(try theme.resolvedPlan())
        XCTAssertThrowsError(try CursorEngine(backend: backend, store: store).apply(theme))
        XCTAssertEqual(try backend.read(arrow).hash, standard.contentHash)
        XCTAssertEqual(try store.loadJournal().status, .clean)
        XCTAssertFalse(store.hasSnapshot)
    }

    func testInterruptedThemeSwitchPreservesStandardSnapshotUntilRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try! FileManager.default.removeItem(at: root) }
        let store = try SnapshotStore(root: root)
        let backend = MemoryBackend()
        let engine = CursorEngine(backend: backend, store: store)
        let arrow = try XCTUnwrap(CursorCatalog.targets(for: "arrow").first)
        let standard = try makeCursor(red: 0)
        let previous = try makeCursor(red: 0.5)
        let next = try makeCursor(red: 1)
        backend.cursors[arrow] = standard
        try engine.refreshSnapshot()
        backend.cursors[arrow] = previous
        try store.saveJournal(
            Journal(status: .applying, themeName: "Next", intended: [arrow: next.contentHash], updatedAt: Date()))

        XCTAssertThrowsError(try engine.refreshSnapshot())
        XCTAssertThrowsError(try engine.apply(CursorTheme(name: "Next", cursors: ["arrow": next])))
        XCTAssertEqual(try store.loadManifest()?.entries[arrow]?.hash, standard.contentHash)
        XCTAssertTrue(try Recovery(backend: backend, store: store).restore().succeeded)
        XCTAssertEqual(try backend.read(arrow).hash, standard.contentHash)
        XCTAssertTrue(try engine.apply(CursorTheme(name: "Next", cursors: ["arrow": next])).succeeded)
    }

    @MainActor
    func testAutoReapplyAcceptsRegisteredImageMatchingBothSnapshotAndTheme() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try! FileManager.default.removeItem(at: root) }
        let store = try SnapshotStore(root: root)
        let backend = MemoryBackend()
        let arrow = try XCTUnwrap(CursorCatalog.targets(for: "arrow").first)
        let standard = try makeCursor(red: 0)
        backend.cursors[arrow] = standard
        let theme = CursorTheme(name: "Standard look", cursors: ["arrow": standard])
        XCTAssertTrue(try CursorEngine(backend: backend, store: store).apply(theme).succeeded)
        let before = try store.loadJournal().changeToken
        var config = AutoReapply.Config()
        config.verifyDelays = []
        let autoReapply = AutoReapply(
            store: store, config: config, makeBackend: { backend }, notify: { _ in }, log: { _ in })
        autoReapply.evaluate(reasons: ["test"], knownCause: false)
        XCTAssertEqual(try store.loadJournal().changeToken, before)
        XCTAssertTrue(try store.loadHelperState().reappliedAt.isEmpty)
        backend.cursors[arrow] = nil
        autoReapply.evaluate(reasons: ["test"], knownCause: false)
        XCTAssertEqual(try backend.read(arrow).hash, standard.contentHash)
        XCTAssertEqual(try store.loadHelperState().reappliedAt.count, 1)
    }

    private func makeCursor(red: CGFloat) throws -> CursorRep {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: red, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return CursorRep(
            size: CGSize(width: 2, height: 2), hotspot: .zero, frameCount: 1, frameDuration: 0,
            images: [try XCTUnwrap(context.makeImage())])
    }

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
        let rep = CursorRep(
            size: CGSize(width: 16, height: 16), hotspot: .zero,
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

private final class MemoryBackend: CursorBackend {
    var cursors: [String: CursorRep] = [:]

    func read(_ name: String) throws -> ReadResult { cursors[name].map(ReadResult.registered) ?? .unregistered }
    func register(_ name: String, _ rep: CursorRep) throws { cursors[name] = rep }
    func remove(_ name: String) throws { cursors[name] = nil }
    func registerSystemDefault(coreCursorID id: Int) throws { XCTFail("Unexpected default registration for \(id)") }
}
