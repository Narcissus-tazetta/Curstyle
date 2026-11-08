import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 1つのカーソル名に登録される内容。
/// アニメは各解像度の画像に frameCount 枚を縦に並べた1枚で表す(OS の登録形式と同じ)。
/// images は解像度違い(1x, 2x, ...)の並び。
public struct CursorRep: Sendable {
    public var size: CGSize
    public var hotspot: CGPoint
    public var frameCount: Int
    public var frameDuration: Double
    public var images: [CGImage]

    public init(size: CGSize, hotspot: CGPoint, frameCount: Int, frameDuration: Double, images: [CGImage]) {
        self.size = size
        self.hotspot = hotspot
        self.frameCount = frameCount
        self.frameDuration = frameDuration
        self.images = images
    }

    /// 表示に効く内容のハッシュ。画像は sRGB RGBA8 に描き直してから比べるので、
    /// 色空間の表現が違うだけの同一画像は同じハッシュになる。
    /// frameDuration は WindowServer が Float32 で保持する(0.1 を登録すると 0.10000000149 が返る)ため、
    /// Float32 に丸めてから比べる。
    public var contentHash: String {
        var hasher = SHA256()
        hasher.update(
            data: Data(
                "\(size.width)x\(size.height);\(hotspot.x),\(hotspot.y);\(frameCount);\(Float(frameDuration));".utf8))
        for image in images {
            hasher.update(data: Data("\(image.width)x\(image.height);".utf8))
            hasher.update(data: rgbaBytes(image))
        }
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public var summary: String {
        let dims = images.map { "\($0.width)x\($0.height)" }.joined(separator: ",")
        return String(
            format: "size=%gx%g hot=(%g,%g) frames=%d dur=%.4f images=[%@]",
            size.width, size.height, hotspot.x, hotspot.y, frameCount, frameDuration, dims)
    }

    /// テーマ由来の画像だけに適用する。OS が登録した標準画像は size と画像寸法が
    /// 食い違うことがある(IBeamS: size 22x23 / 画像 23x22)ので、スナップショットには使わない。
    public func validate() throws {
        func fail(_ reason: String) -> CursorKitError { .invalidCursor(reason) }
        guard (1...24).contains(frameCount) else { throw fail("frameCount=\(frameCount) は 1〜24 の範囲外") }
        guard size.width >= 1, size.height >= 1, size.width <= 256, size.height <= 256 else {
            throw fail("size=\(size) は 1〜256pt の範囲外")
        }
        guard (0...size.width).contains(hotspot.x), (0...size.height).contains(hotspot.y) else {
            throw fail("hotspot=\(hotspot) が size=\(size) の外")
        }
        if frameCount > 1 {
            guard frameDuration > 0, frameDuration <= 2 else {
                throw fail("frameDuration=\(frameDuration) は (0, 2] 秒の範囲外")
            }
        }
        guard !images.isEmpty, images.count <= 8 else { throw fail("画像の数 \(images.count) は 1〜8 の範囲外") }
        var scales = Set<Int>()
        for image in images {
            let scale = Double(image.width) / size.width
            guard scale >= 1, scale == scale.rounded() else {
                throw fail("画像幅 \(image.width) が size.width \(size.width) の整数倍でない")
            }
            let expectedHeight = size.height * scale * Double(frameCount)
            guard Double(image.height) == expectedHeight else {
                throw fail("画像 \(image.width)x\(image.height) の高さが \(Int(expectedHeight)) でない(\(frameCount) フレーム縦並び)")
            }
            guard scales.insert(Int(scale)).inserted else { throw fail("倍率 \(Int(scale))x の画像が重複") }
        }
        guard scales.contains(1) || scales.contains(2) else { throw fail("1x か 2x の画像が必要") }
    }
}

public enum CursorKitError: Error, CustomStringConvertible {
    case symbolMissing(String)
    case backend(operation: String, name: String, code: Int32)
    case invalidCursor(String)
    case unknownCursorKey(String)
    case snapshot(String)
    case theme(String)
    case busy(String)
    case injectedFailure(String)
    case io(String)

    public var description: String {
        switch self {
        case .symbolMissing(let s): "非公開シンボル \(s) がこの OS に無い(未対応)"
        case .backend(let op, let name, let code): "\(op)(\(name)) が err=\(code) を返した"
        case .invalidCursor(let r): "不正なカーソル: \(r)"
        case .unknownCursorKey(let k): "未知のカーソル名: \(k)"
        case .snapshot(let r): "スナップショット: \(r)"
        case .theme(let r): "テーマ: \(r)"
        case .busy(let r): r
        case .injectedFailure(let r): "注入した失敗: \(r)"
        case .io(let r): r
        }
    }
}

private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgbaBytes(_ image: CGImage) -> Data {
    let width = image.width
    let height = image.height
    var data = Data(count: width * height * 4)
    data.withUnsafeMutableBytes { raw in
        let ctx = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return data
}

/// contentHash と同じ sRGB RGBA8 表現に揃える。保存→読み込みでハッシュを保つため。
func normalizedImage(_ image: CGImage) -> CGImage {
    let ctx = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CursorKitError.io("PNG を作れない: \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw CursorKitError.io("PNG を書けない: \(url.path)") }
}

func readPNG(at url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { throw CursorKitError.io("画像を読めない: \(url.path)") }
    return image
}
