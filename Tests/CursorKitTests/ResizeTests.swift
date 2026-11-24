import CoreGraphics
import Foundation
import XCTest

@testable import CursorKit

final class ResizeTests: XCTestCase {
    func testResizePreservesValidThemeWithEightScalesAndNoRetinaImage() throws {
        var rep = try pixelArtRep()
        let original = rep.images[0]
        let scales = [1, 3, 4, 5, 6, 7, 8, 9]
        rep.images = try scales.map { scale in
            try resampleStrip(original, frameCount: rep.frameCount, to: CGSize(width: 32 * scale, height: 32 * scale))
        }
        try rep.validate()

        let resized = try rep.scalingSize(by: 0.5)

        try resized.validate()
        XCTAssertEqual(resized.images.map(\.width), scales.map { 16 * $0 })
    }

    func testResizingASavedThemeAgainMatchesResizingTheOriginalOnce() throws {
        let original = CursorTheme(name: "Pixel", cursors: ["arrow": try pixelArtRep()])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try! FileManager.default.removeItem(at: directory) }

        try original.scalingSize(by: 42.0 / 32).write(directory: directory)
        let twice = try CursorTheme.load(directory: directory).scalingSize(by: 50.0 / 42)
        let once = try original.scalingSize(by: 50.0 / 32)

        XCTAssertEqual(twice.fingerprint, once.fingerprint)
    }

    func testResizingBackToTheOriginalSizeRestoresTheOriginalImage() throws {
        let rep = try pixelArtRep()
        let restored = try rep.scalingSize(by: 42.0 / 32).scalingSize(by: 32.0 / 42)

        let restored1x = try XCTUnwrap(restored.images.first { $0.width == 32 })
        XCTAssertEqual(rgbaBytes(restored1x), rgbaBytes(rep.images[0]))
    }

    /// 1ビット透過・少数色の 32px、2コマのアニメ。
    private func pixelArtRep() throws -> CursorRep {
        let colors: [CGColor] = [
            CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1),
        ]
        let frames = colors.map { color -> CGImage in
            let context = CGContext(
                data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(color)
            context.fill(CGRect(x: 3, y: 5, width: 11, height: 17))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 14, y: 5, width: 7, height: 9))
            return context.makeImage()!
        }
        let strip = try WindowsCursorImporter.stack(frames)
        XCTAssertTrue(isPixelArt(strip))
        return CursorRep(
            size: CGSize(width: 32, height: 32), hotspot: .zero, frameCount: 2, frameDuration: 0.1, images: [strip])
    }
}
