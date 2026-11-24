import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import CursorKit

final class AnimationImportTests: XCTestCase {
    func testWindowsImportKeepsOriginalResolutionAtThreeAndFourPixelsPerPoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try! FileManager.default.removeItem(at: directory) }
        try curData(index: 0, scale: 24).write(to: directory.appendingPathComponent("Normal.cur"))
        for scale in [3, 4] {
            let imported = try WindowsCursorImporter.importTheme(
                directory: directory, name: "Windows", pixelsPerPoint: scale)
            let rep = try XCTUnwrap(imported.theme.cursors["arrow"])
            XCTAssertEqual(rep.size.width, Double(48 / scale))
            XCTAssertEqual(rep.images.map(\.width), [48 / scale, 48])
            try rep.validate()
        }
    }

    func testArbitraryFrameCountsPreserveCycleAndSampleTheOriginalTimeline() throws {
        for count in [2, 23, 24, 25, 26, 30, 47, 48, 49, 54, 59, 60, 61, 97, 100, 127, 144, 255, 256, 257, 1000] {
            let inputDuration = 1.0 / 60
            let rep = CursorRep(
                size: CGSize(width: 2, height: 2), hotspot: CGPoint(x: 1, y: 1),
                frameCount: count, frameDuration: inputDuration,
                images: try [1, 2].map { scale in
                    try WindowsCursorImporter.stack((0..<count).map { image(index: $0, scale: scale) })
                })
            let imported = try rep.importingAnimation()
            let output = imported.rep
            XCTAssertEqual(output.frameCount, min(count, 24), "input=\(count)")
            XCTAssertEqual(imported.adjustment != nil, count > 24)
            XCTAssertEqual(
                output.frameDuration * Double(output.frameCount), inputDuration * Double(count), accuracy: 0.000001)
            XCTAssertEqual(output.hotspot, rep.hotspot)
            try output.validate()
            if count <= 24 { XCTAssertEqual(output.contentHash, rep.contentHash) }
            for (i, strip) in output.images.enumerated() {
                let scale = i + 1
                XCTAssertEqual(strip.width, 2 * scale)
                XCTAssertEqual(strip.height, 2 * scale * output.frameCount)
                var previousIndex = -1
                for frame in 0..<output.frameCount {
                    let crop = strip.cropping(
                        to: CGRect(x: 0, y: frame * 2 * scale, width: 2 * scale, height: 2 * scale))!
                    let bytes = rgbaBytes(crop)
                    let sourceIndex = Int(bytes[0]) + 256 * Int(bytes[1])
                    let sampleTime = Double(frame) * output.frameDuration
                    XCTAssertGreaterThan(sourceIndex, previousIndex)
                    XCTAssertLessThan(sourceIndex, count)
                    XCTAssertLessThanOrEqual(Double(sourceIndex) * inputDuration, sampleTime + 1e-10)
                    XCTAssertGreaterThan(Double(sourceIndex + 1) * inputDuration, sampleTime + 1e-10)
                    previousIndex = sourceIndex
                }
            }
        }
    }

    func testWithinLimitIsUnchangedAndInvalidInputStillFails() throws {
        for count in [1, 2, 12, 23, 24] {
            let rep = CursorRep(
                size: CGSize(width: 2, height: 2), hotspot: .zero, frameCount: count,
                frameDuration: count > 1 ? 0.1 : 0,
                images: [try WindowsCursorImporter.stack((0..<count).map { image(index: $0) })])
            let imported = try rep.importingAnimation()
            XCTAssertNil(imported.adjustment)
            XCTAssertEqual(imported.rep.contentHash, rep.contentHash)
        }
        var invalid = CursorRep(
            size: CGSize(width: 2, height: 2), hotspot: .zero, frameCount: 54, frameDuration: 0.1,
            images: [try WindowsCursorImporter.stack((0..<54).map { image(index: $0) })])
        invalid.hotspot.x = 3
        XCTAssertThrowsError(try invalid.importingAnimation())
        invalid.hotspot = .zero
        invalid.frameCount = 0
        XCTAssertThrowsError(try invalid.importingAnimation())
    }

    func testGIFImportReducesFramesAndReportsAdjustment() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gif")
        defer { try! FileManager.default.removeItem(at: file) }
        try gifData(delays: Array(repeating: 10, count: 54)).write(to: file)
        let source = CGImageSourceCreateWithURL(file as CFURL, nil)!
        XCTAssertEqual(CGImageSourceGetCount(source), 54)
        let imported = try CursorRep.fromImageFile(file, pointSize: 16)
        XCTAssertNotNil(imported.adjustment)
        XCTAssertEqual(imported.rep.frameCount, 24)
        XCTAssertEqual(imported.rep.frameDuration * 24, 5.4, accuracy: 0.000001)
        try imported.rep.validate()
    }

    func testCapeImportReducesFramesWithoutSkippingCursor() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).cape")
        defer { try! FileManager.default.removeItem(at: file) }
        let strip = try WindowsCursorImporter.stack((0..<54).map { image(index: $0) })
        let png = NSMutableData()
        let dest = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, strip, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let plist: [String: Any] = [
            "CapeName": "Long animation",
            "Cursors": [
                "com.apple.coregraphics.ArrowS": [
                    "PointsWide": 2, "PointsHigh": 2, "HotSpotX": 1, "HotSpotY": 1,
                    "FrameCount": 54, "FrameDuration": 0.1, "Representations": [png as Data],
                ]
            ],
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: file)
        let imported = try CursorTheme.importSource(file, name: nil, pixelsPerPoint: 1)
        XCTAssertTrue(imported.skipped.isEmpty)
        XCTAssertEqual(imported.adjustments.count, 1)
        XCTAssertEqual(imported.theme.cursors["arrow"]!.frameCount, 24)
        XCTAssertEqual(imported.theme.cursors["arrow"]!.frameDuration * 24, 5.4, accuracy: 0.000001)
        _ = try imported.theme.resolvedPlan()
    }

    func testThemeFolderImportReducesFramesAndReportsAdjustment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rep = CursorRep(
            size: CGSize(width: 2, height: 2), hotspot: .zero, frameCount: 54, frameDuration: 0.1,
            images: [try WindowsCursorImporter.stack((0..<54).map { image(index: $0) })])
        try CursorTheme(name: "Long animation", cursors: ["arrow": rep]).write(directory: directory)
        defer { try! FileManager.default.removeItem(at: directory) }
        let imported = try CursorTheme.importSource(directory, name: nil, pixelsPerPoint: 1)
        XCTAssertEqual(imported.adjustments.count, 1)
        XCTAssertEqual(imported.theme.cursors["arrow"]!.frameCount, 24)
        XCTAssertEqual(imported.theme.cursors["arrow"]!.frameDuration * 24, 5.4, accuracy: 0.000001)
        _ = try imported.theme.resolvedPlan()
    }

    func testVariableGIFDelaysPreserveTheTimelineWhenExpansionExceedsLimit() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gif")
        try gifData(delays: [7, 29]).write(to: file)
        defer { try! FileManager.default.removeItem(at: file) }
        let imported = try CursorRep.fromImageFile(file, pointSize: 16)
        let rep = imported.rep
        XCTAssertNotNil(imported.adjustment)
        XCTAssertEqual(rep.frameCount, 24)
        XCTAssertEqual(rep.frameDuration * 24, 0.36, accuracy: 0.000001)
        for strip in rep.images {
            let height = strip.height / rep.frameCount
            for i in 0..<rep.frameCount {
                let crop = strip.cropping(to: CGRect(x: 0, y: i * height, width: strip.width, height: height))!
                let firstPixel = rgbaBytes(crop)[0]
                XCTAssertEqual(firstPixel, Double(i) * rep.frameDuration < 0.07 ? 0 : 255)
            }
        }
        try rep.validate()
    }

    func testSlowAnimationPreservesCycleBeyondTwoSecondsPerOutputFrame() throws {
        for (count, duration) in [(60, 1.0), (25, 2.0), (24, 2.5)] {
            let rep = CursorRep(
                size: CGSize(width: 2, height: 2), hotspot: .zero,
                frameCount: count, frameDuration: duration,
                images: [try WindowsCursorImporter.stack((0..<count).map { image(index: $0) })])
            let imported = try rep.importingAnimation()
            XCTAssertEqual(imported.rep.frameCount, 24)
            XCTAssertEqual(imported.rep.frameDuration * 24, Double(count) * duration, accuracy: 0.000001)
            try imported.rep.validate()
        }
    }

    func testUnrepresentableFrameDurationsAreRejected() throws {
        for duration in [
            0, -1, Double.nan, Double.infinity, Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude,
        ] {
            let rep = CursorRep(
                size: CGSize(width: 2, height: 2), hotspot: .zero,
                frameCount: 2, frameDuration: duration,
                images: [try WindowsCursorImporter.stack([image(index: 0), image(index: 1)])])
            XCTAssertThrowsError(try rep.importingAnimation())
        }
    }

    func testExtremeGIFDelaysPreserveCycleAndFrameSelection() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gif")
        defer { try! FileManager.default.removeItem(at: file) }
        try gifData(delays: [65535, 65534]).write(to: file)
        let imported = try CursorRep.fromImageFile(file, pointSize: 16)
        XCTAssertNotNil(imported.adjustment)
        XCTAssertEqual(imported.rep.frameCount, 24)
        XCTAssertEqual(imported.rep.frameDuration * 24, 1310.69, accuracy: 1e-9)
        for strip in imported.rep.images {
            let height = strip.height / 24
            for i in 0..<24 {
                let crop = try XCTUnwrap(
                    strip.cropping(to: CGRect(x: 0, y: i * height, width: strip.width, height: height)))
                XCTAssertEqual(rgbaBytes(crop)[0], i <= 12 ? 0 : 255)
            }
        }
        try imported.rep.validate()
    }

    func testVariableANIDelaysPreserveCycleAndFrameSelection() throws {
        func chunk(_ name: String, _ body: Data) -> Data {
            Data(name.utf8) + words([UInt32(body.count)]) + body + (body.count % 2 == 1 ? Data([0]) : Data())
        }
        for rates: [UInt32] in [[7, 29], [3000, 3001], [UInt32.max - 1, UInt32.max]] {
            let body =
                Data("ACON".utf8)
                + chunk("anih", words([36, 2, 2, 0, 0, 0, 0, 1, 1]))
                + chunk("rate", words(rates))
                + chunk(
                    "LIST",
                    Data("fram".utf8) + chunk("icon", curData(index: 0, scale: 16))
                        + chunk("icon", curData(index: 1, scale: 16)))
            let ani = Data("RIFF".utf8) + words([UInt32(body.count)]) + body
            let imported = try WindowsCursorImporter.cursorRep(from: ani, isAnimated: true, pixelsPerPoint: 1)
            XCTAssertNotNil(imported.adjustment)
            XCTAssertEqual(imported.rep.frameCount, 24)
            let total = Int(rates[0]) + Int(rates[1])
            XCTAssertEqual(imported.rep.frameDuration * 24, Double(total) / 60, accuracy: 1e-6)
            for strip in imported.rep.images {
                let height = strip.height / 24
                for i in 0..<24 {
                    let crop = try XCTUnwrap(
                        strip.cropping(to: CGRect(x: 0, y: i * height, width: strip.width, height: height)))
                    XCTAssertEqual(rgbaBytes(crop)[0], i * total / 24 < Int(rates[0]) ? 0 : 1)
                }
            }
            try imported.rep.validate()
        }
    }

    func testTimelineMatchesExpandedSamplingIncludingFrameBoundaries() {
        for durations in [[1, 1], [2, 4], [7, 29], [12, 24, 36], [1, 23, 1], Array(repeating: 3, count: 54)] {
            let expanded = durations.enumerated().flatMap { Array(repeating: $0.offset, count: $0.element) }
            let timeline = AnimationTimeline(durations: durations, ticksPerSecond: 60)
            let count = min(expanded.count, 24)
            // 最大公約数がある場合は元の最小間隔を保つため、展開後の全コマが必要とは限らない。
            for (i, index) in timeline.indices.enumerated() {
                XCTAssertEqual(index, expanded[i * expanded.count / timeline.indices.count])
            }
            XCTAssertLessThanOrEqual(timeline.indices.count, count)
            XCTAssertEqual(
                timeline.frameDuration * Double(timeline.indices.count), Double(durations.reduce(0, +)) / 60,
                accuracy: 1e-9)
        }
    }

    private func curData(index: Int, scale: Int) -> Data {
        let frame = image(index: index, scale: scale)
        let png = NSMutableData()
        let dest = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, frame, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        var data = Data([0, 0, 2, 0, 1, 0, UInt8(frame.width), UInt8(frame.height), 0, 0, 0, 0, 0, 0])
        data += words([UInt32(png.length), 22])
        data += png as Data
        return data
    }

    private func words(_ values: [UInt32]) -> Data {
        Data(values.flatMap { value in (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } })
    }

    private func gifData(delays: [UInt16]) -> Data {
        // エンコーダーの最適化に入力のコマ数が左右されないよう、GIFを直接組む。
        var gif = Data("GIF89a".utf8)
        gif.append(contentsOf: [1, 0, 1, 0, 0x80, 0, 0, 0, 0, 0, 255, 255, 255])
        for (i, delay) in delays.enumerated() {
            gif.append(contentsOf: [0x21, 0xf9, 4, 0, UInt8(delay & 255), UInt8(delay >> 8), 0, 0])
            gif.append(contentsOf: [0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, i % 2 == 0 ? 0x44 : 0x4c, 1, 0])
        }
        gif.append(0x3b)
        return gif
    }

    private func image(index: Int, scale: Int = 1) -> CGImage {
        let ctx = CGContext(
            data: nil, width: 2 * scale, height: 2 * scale, bitsPerComponent: 8, bytesPerRow: 2 * scale * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(
            CGColor(
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                components: [CGFloat(index % 256) / 255, CGFloat(index / 256) / 255, 0, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: 2 * scale, height: 2 * scale))
        return ctx.makeImage()!
    }
}

final class CursorSizeScalingTests: XCTestCase {
    private func rep(frames: Int) throws -> CursorRep {
        func strip(_ scale: Int) throws -> CGImage {
            try WindowsCursorImporter.stack(
                (0..<frames).map { _ in
                    let ctx = CGContext(
                        data: nil, width: 16 * scale, height: 16 * scale, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                    ctx.fill(CGRect(x: 0, y: 0, width: 16 * scale, height: 16 * scale))
                    return ctx.makeImage()!
                })
        }
        return CursorRep(
            size: CGSize(width: 16, height: 16), hotspot: CGPoint(x: 4, y: 8), frameCount: frames,
            frameDuration: frames > 1 ? 0.1 : 0, images: try [1, 2].map(strip))
    }

    func testScalingKeepsRegistrationInvariants() throws {
        for frames in [1, 6] {
            for factor in [0.5, 1.5, 2.0] {
                let scaled = try rep(frames: frames).scalingSize(by: factor)
                try scaled.validate()
                XCTAssertEqual(scaled.size, CGSize(width: 16 * factor, height: 16 * factor))
                XCTAssertEqual(scaled.hotspot, CGPoint(x: 4 * factor, y: 8 * factor))
                XCTAssertEqual(scaled.frameCount, frames)
                XCTAssertEqual(scaled.frameDuration, frames > 1 ? 0.1 : 0)
            }
        }
    }

    func testThemeScalingSharesResultAcrossIdenticalCursors() throws {
        let a = try rep(frames: 1)
        let theme = CursorTheme(name: "t", cursors: ["arrow": a, "ibeam": a])
        let scaled = try theme.scalingSize(by: 2)
        XCTAssertEqual(scaled.cursors["arrow"]!.contentHash, scaled.cursors["ibeam"]!.contentHash)
    }
}
