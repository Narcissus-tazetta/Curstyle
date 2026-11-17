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
    /// 大きさを変える前の画像(images と同じくコマを縦に並べたもの)。大きさを変えるたびに images から作り直すと、
    /// 補間のにじみが重なり、ドット絵も判定から外れる。そこで最初に変える前の画像を残し、毎回ここから作る。
    /// OS には登録しない。
    public var source: CGImage?

    public init(
        size: CGSize, hotspot: CGPoint, frameCount: Int, frameDuration: Double, images: [CGImage],
        source: CGImage? = nil
    ) {
        self.size = size
        self.hotspot = hotspot
        self.frameCount = frameCount
        self.frameDuration = frameDuration
        self.images = images
        self.source = source
    }

    /// 表示に効く内容のハッシュ。source は表示されず、WindowServer から読み戻した内容と比べる用途もあるので含めない。
    /// 画像は sRGB RGBA8 に描き直してから比べるので、
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

    public func animationFrameIndex(at elapsed: TimeInterval) -> Int {
        guard frameCount > 1, frameDuration > 0 else { return 0 }
        // 全経過時間を Int にすると、正当な短いフレーム間隔でも整数範囲を超える。
        let cycle = frameDuration * Double(frameCount)
        let phase = elapsed.truncatingRemainder(dividingBy: cycle)
        return min(Int(phase / frameDuration), frameCount - 1)
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
        try validate(frameLimit: Self.maxAnimationFrames)
    }

    // SLSRegisterCursorWithImages2 は25コマ以上をエラー1000で拒否する。
    static let maxAnimationFrames = 24

    func importingAnimation() throws -> (rep: CursorRep, adjustment: String?) {
        try validate(frameLimit: max(frameCount, Self.maxAnimationFrames))
        guard frameCount > Self.maxAnimationFrames else { return (self, nil) }
        let count = Self.maxAnimationFrames
        func decimated(_ strip: CGImage) throws -> CGImage {
            let height = strip.height / frameCount
            let frames = try (0..<count).map { i in
                let index = i * frameCount / count
                guard
                    let frame = strip.cropping(
                        to: CGRect(x: 0, y: index * height, width: strip.width, height: height))
                else { throw CursorKitError.io(L10n.text("コマ {0} を切り出せない", String(describing: index))) }
                return frame
            }
            return try WindowsCursorImporter.stack(frames)
        }
        var rep = self
        rep.images = try images.map(decimated)
        rep.source = try source.map(decimated)
        rep.frameCount = count
        rep.frameDuration = frameDuration * Double(frameCount) / Double(count)
        try rep.validate()
        return (
            rep,
            L10n.text(
                "{0} → {1} コマに間引きました（1周の時間は維持・動きの滑らかさは低下します）", String(describing: frameCount), String(describing: count)
            )
        )
    }

    private func validate(frameLimit: Int) throws {
        func fail(_ reason: String) -> CursorKitError { .invalidCursor(reason) }
        guard (1...frameLimit).contains(frameCount) else {
            throw fail(
                L10n.text("frameCount={0} は 1〜{1} の範囲外", String(describing: frameCount), String(describing: frameLimit))
            )
        }
        guard size.width >= 1, size.height >= 1, size.width <= 256, size.height <= 256 else {
            throw fail(L10n.text("size={0} は 1〜256pt の範囲外", String(describing: size)))
        }
        guard (0...size.width).contains(hotspot.x), (0...size.height).contains(hotspot.y) else {
            throw fail(L10n.text("hotspot={0} が size={1} の外", String(describing: hotspot), String(describing: size)))
        }
        if frameCount > 1 {
            let storedDuration = Float(frameDuration)
            guard storedDuration.isFinite, storedDuration > 0 else {
                throw fail(L10n.text("frameDuration={0} は Float32 で表せる正の有限な秒数で指定する", String(describing: frameDuration)))
            }
        }
        guard !images.isEmpty, images.count <= 8 else {
            throw fail(L10n.text("画像の数 {0} は 1〜8 の範囲外", String(describing: images.count)))
        }
        var scales = Set<Int>()
        for image in images {
            let scale = Double(image.width) / size.width
            guard scale >= 1, scale == scale.rounded() else {
                throw fail(
                    L10n.text(
                        "画像幅 {0} が size.width {1} の整数倍でない", String(describing: image.width),
                        String(describing: size.width)))
            }
            let expectedHeight = size.height * scale * Double(frameCount)
            guard Double(image.height) == expectedHeight else {
                throw fail(
                    L10n.text(
                        "画像 {0}x{1} の高さが {2} でない({3} フレーム縦並び)", String(describing: image.width),
                        String(describing: image.height), String(describing: Int(expectedHeight)),
                        String(describing: frameCount)))
            }
            guard scales.insert(Int(scale)).inserted else {
                throw fail(L10n.text("倍率 {0}x の画像が重複", String(describing: Int(scale))))
            }
        }
        guard scales.contains(1) || scales.contains(2) else { throw fail(L10n.text("1x か 2x の画像が必要")) }
        if let source, source.height % frameCount != 0 {
            throw fail(
                "source: "
                    + L10n.text(
                        "画像の高さ {0} が {1} コマで割り切れない", String(describing: source.height),
                        String(describing: frameCount)))
        }
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
        case .symbolMissing(let s): L10n.text("非公開シンボル {0} がこの OS に無い(未対応)", String(describing: s))
        case .backend(let op, let name, let code):
            L10n.text(
                "{0}({1}) が err={2} を返した", String(describing: op), String(describing: name), String(describing: code))
        case .invalidCursor(let r): L10n.text("不正なカーソル: {0}", String(describing: r))
        case .unknownCursorKey(let k): L10n.text("未知のカーソル名: {0}", String(describing: k))
        case .snapshot(let r): L10n.text("スナップショット: {0}", String(describing: r))
        case .theme(let r): L10n.text("テーマ: {0}", String(describing: r))
        case .busy(let r): r
        case .injectedFailure(let r): L10n.text("注入した失敗: {0}", String(describing: r))
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

func imageHash(_ image: CGImage) -> String {
    var hasher = SHA256()
    hasher.update(data: Data("\(image.width)x\(image.height);".utf8))
    hasher.update(data: rgbaBytes(image))
    return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
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
    else { throw CursorKitError.io(L10n.text("PNG を作れない: {0}", String(describing: url.path))) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw CursorKitError.io(L10n.text("PNG を書けない: {0}", String(describing: url.path)))
    }
}

func readPNG(at url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { throw CursorKitError.io(L10n.text("画像を読めない: {0}", String(describing: url.path))) }
    return image
}
