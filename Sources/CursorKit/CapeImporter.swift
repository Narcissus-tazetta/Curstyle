import CoreGraphics
import Foundation
import ImageIO

/// .cape(plist の Cursors に識別子ごとの FrameCount / FrameDuration / HotSpotX,Y / PointsWide,High /
/// Representations を持つ形式)を CursorTheme に変換する。
public enum CapeImporter {
    public struct Result {
        public var theme: CursorTheme
        /// 取り込まなかった識別子と理由。
        public var skipped: [String]
        public var adjustments: [String]
    }

    /// 24コマを超えるアニメは取り込み時に間引くが、元のコマ数にも現実的な上限を置く。
    static let maxFrameCount = 100_000.0

    public static func importTheme(file: URL, name: String?) throws -> Result {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil)
        } catch {
            throw CursorKitError.theme(
                L10n.text(
                    "{0} を plist として読めない: {1}", String(describing: file.lastPathComponent), String(describing: error)))
        }
        guard let root = plist as? [String: Any], let entries = root["Cursors"] as? [String: [String: Any]] else {
            throw CursorKitError.theme(
                L10n.text("{0} に Cursors が無い(.cape ではない)", String(describing: file.lastPathComponent)))
        }

        var cursors: [String: CursorRep] = [:]
        var skipped: [String] = []
        var adjustments: [String] = []
        var usedTargets = Set<String>()
        // Arrow と ArrowS の両方があれば、macOS 27.2 で表示に効く S の方を残す。S を先に処理する。
        for id in entries.keys.sorted(by: { ($0.hasSuffix("S") ? 0 : 1, $0) < ($1.hasSuffix("S") ? 0 : 1, $1) }) {
            guard let key = themeKey(for: id) else {
                skipped.append(L10n.text("{0}(Curstyle が差し替えない名前)", String(describing: id)))
                continue
            }
            guard cursors[key] == nil else { continue }
            do {
                let imported = try cursorRep(entries[id]!).importingAnimation()
                let rep = imported.rep
                // cursor.7 と 8 のように同じ登録先へ当たる組は、先に来た方だけ残す(resolvedPlan が重複を拒否するため)。
                let names = try CursorCatalog.targets(for: key)
                guard names.allSatisfy({ !usedTargets.contains($0) }) else {
                    skipped.append(L10n.text("{0}(ほかの識別子と同じ登録先)", String(describing: id)))
                    continue
                }
                usedTargets.formUnion(names)
                cursors[key] = rep
                if let adjustment = imported.adjustment { adjustments.append("\(key): \(adjustment)") }
            } catch {
                skipped.append("\(id)(\(error))")
            }
        }
        guard !cursors.isEmpty else {
            throw CursorKitError.theme(
                L10n.text(
                    "{0} に取り込めるカーソルが無い: {1}", String(describing: file.lastPathComponent),
                    String(describing: skipped.joined(separator: ", "))))
        }
        let themeName = name ?? (root["CapeName"] as? String) ?? file.deletingPathExtension().lastPathComponent
        return Result(theme: CursorTheme(name: themeName, cursors: cursors), skipped: skipped, adjustments: adjustments)
    }

    /// 画面に出す名前がそのまま役割名になるよう、番号を分かっている役割名に置き換える。
    static func themeKey(for identifier: String) -> String? {
        switch identifier {
        case "com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowS": return "arrow"
        case "com.apple.coregraphics.IBeam", "com.apple.coregraphics.IBeamS": return "ibeam"
        default: break
        }
        guard let id = CursorCatalog.coreCursorID(of: identifier), CursorCatalog.coreCursorIDs.contains(id) else {
            return nil
        }
        if id == 13 { return "pointingHand" }
        return CursorCatalog.roleNames[id] ?? "cursor.\(id)"
    }

    static func cursorRep(_ entry: [String: Any]) throws -> CursorRep {
        func number(_ key: String) throws -> Double {
            guard let n = entry[key] as? NSNumber else {
                throw CursorKitError.invalidCursor(L10n.text("{0} が無い", String(describing: key)))
            }
            return n.doubleValue
        }
        let size = CGSize(width: try number("PointsWide"), height: try number("PointsHigh"))
        let frameCountValue = try number("FrameCount")
        let hotspot = CGPoint(x: try number("HotSpotX"), y: try number("HotSpotY"))
        // plist の数値は何でも入る。Int への変換や画像の確保で落ちないよう、変換の前に範囲を確かめる(NaN も弾かれる)。
        guard (1...256).contains(size.width), (1...256).contains(size.height),
            (1...Self.maxFrameCount).contains(frameCountValue)
        else {
            throw CursorKitError.invalidCursor(
                L10n.text("size={0} frameCount={1} が不正", String(describing: size), String(describing: frameCountValue)))
        }
        let frameCount = Int(frameCountValue)
        // 静止画にも FrameDuration=1 が入っている。登録形式では静止画の間隔は 0。
        let frameDuration = frameCount > 1 ? try number("FrameDuration") : 0

        var images: [CGImage] = []
        for data in entry["Representations"] as? [Data] ?? [] {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
            for i in 0..<CGImageSourceGetCount(source) {
                if let image = CGImageSourceCreateImageAtIndex(source, i, nil) { images.append(normalizedImage(image)) }
            }
        }
        guard !images.isEmpty else { throw CursorKitError.invalidCursor(L10n.text("画像を読めない")) }

        // 整数倍率で高さも合う画像はそのまま使う。1x / 2x が無い(10倍の画像だけ、など)ときは
        // 最大の画像から 1x と 2x を作る。
        var byScale: [Int: CGImage] = [:]
        for image in images {
            let scale = Double(image.width) / size.width
            guard scale == scale.rounded(), (1...4).contains(Int(scale)),
                Double(image.height) == size.height * scale * Double(frameCount)
            else { continue }
            byScale[Int(scale)] = byScale[Int(scale)] ?? image
        }
        if byScale[1] == nil && byScale[2] == nil {
            let largest = images.max { $0.width < $1.width }!
            guard largest.height % frameCount == 0 else {
                throw CursorKitError.invalidCursor(
                    L10n.text(
                        "画像の高さ {0} が {1} コマで割り切れない", String(describing: largest.height), String(describing: frameCount))
                )
            }
            for scale in [1, 2] {
                byScale[scale] = try resampleStrip(
                    largest, frameCount: frameCount,
                    to: CGSize(width: size.width * Double(scale), height: size.height * Double(scale)))
            }
        }
        return CursorRep(
            size: size, hotspot: hotspot, frameCount: frameCount, frameDuration: frameDuration,
            images: byScale.keys.sorted().map { byScale[$0]! })
    }
}

/// 縦に並んだコマを1コマずつ拡大・縮小して並べ直す。
/// ドット絵をなめらかな補間で半端な倍率(32px → 84px など)に拡大すると、画素の幅が不揃いになり輪郭もにじむ。
/// そこで最近傍補間で整数倍に広げてから目標の大きさへ縮める。混ざるのは画素の境目の1画素だけになる。
func resampleStrip(_ strip: CGImage, frameCount: Int, to frameSize: CGSize) throws -> CGImage {
    let sourceWidth = strip.width
    let sourceHeight = strip.height / frameCount
    let ratio = max(frameSize.width / Double(sourceWidth), frameSize.height / Double(sourceHeight))
    guard ratio > 1, isPixelArt(strip) else {
        return try drawFrames(strip, frameCount: frameCount, to: frameSize, quality: .high)
    }
    let factor = Int(ratio.rounded(.up))
    let enlarged = try drawFrames(
        strip, frameCount: frameCount, to: CGSize(width: sourceWidth * factor, height: sourceHeight * factor),
        quality: .none)
    if enlarged.width == Int(frameSize.width.rounded())
        && enlarged.height / frameCount == Int(frameSize.height.rounded())
    {
        return enlarged
    }
    return try drawFrames(enlarged, frameCount: frameCount, to: frameSize, quality: .high)
}

/// 半透明の画素がほぼ無く(Windows の .cur / .ani は1ビットの透過が多い)、色数も少ない画像をドット絵とみなす。
/// 手元の実測ではドット絵テーマは半透明 0%・40〜60色、なめらかなカーソル(Bibata など)は半透明 29〜90%。
/// 色数の条件は、透過が1ビットしかない GIF のイラストを最近傍で拡大してカクカクにしないため。
func isPixelArt(_ image: CGImage) -> Bool {
    let bytes = rgbaBytes(image)
    var visible = 0
    var partial = 0
    var colors = Set<UInt32>()
    bytes.withUnsafeBytes { raw in
        let p = raw.bindMemory(to: UInt8.self)
        for i in stride(from: 0, to: p.count, by: 4) where p[i + 3] > 0 {
            visible += 1
            if p[i + 3] < 255 { partial += 1 }
            if colors.count <= pixelArtMaxColors {
                colors.insert(UInt32(p[i]) << 24 | UInt32(p[i + 1]) << 16 | UInt32(p[i + 2]) << 8 | UInt32(p[i + 3]))
            }
        }
    }
    return visible > 0 && partial * 100 <= visible && colors.count <= pixelArtMaxColors
}

private let pixelArtMaxColors = 128

private func drawFrames(_ strip: CGImage, frameCount: Int, to frameSize: CGSize, quality: CGInterpolationQuality)
    throws -> CGImage
{
    let w = Int(frameSize.width.rounded())
    let h = Int(frameSize.height.rounded())
    let sourceHeight = strip.height / frameCount
    guard
        let ctx = CGContext(
            data: nil, width: w, height: h * frameCount, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CursorKitError.io(L10n.text("縮小先の画像を作れない")) }
    ctx.interpolationQuality = quality
    for i in 0..<frameCount {
        guard
            let frame = strip.cropping(
                to: CGRect(x: 0, y: i * sourceHeight, width: strip.width, height: sourceHeight))
        else { throw CursorKitError.io(L10n.text("コマ {0} を切り出せない", String(describing: i))) }
        // CGContext は下が原点。先頭コマを上に置く。
        ctx.draw(frame, in: CGRect(x: 0, y: (frameCount - 1 - i) * h, width: w, height: h))
    }
    return ctx.makeImage()!
}
