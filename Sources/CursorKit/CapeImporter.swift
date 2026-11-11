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

    public static func importTheme(file: URL, name: String?) throws -> Result {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil)
        } catch {
            throw CursorKitError.theme("\(file.lastPathComponent) を plist として読めない: \(error)")
        }
        guard let root = plist as? [String: Any], let entries = root["Cursors"] as? [String: [String: Any]] else {
            throw CursorKitError.theme("\(file.lastPathComponent) に Cursors が無い(.cape ではない)")
        }

        var cursors: [String: CursorRep] = [:]
        var skipped: [String] = []
        var adjustments: [String] = []
        var usedTargets = Set<String>()
        // Arrow と ArrowS の両方があれば、macOS 27.2 で表示に効く S の方を残す。S を先に処理する。
        for id in entries.keys.sorted(by: { ($0.hasSuffix("S") ? 0 : 1, $0) < ($1.hasSuffix("S") ? 0 : 1, $1) }) {
            guard let key = themeKey(for: id) else {
                skipped.append("\(id)(Curstyle が差し替えない名前)")
                continue
            }
            guard cursors[key] == nil else { continue }
            do {
                let imported = try cursorRep(entries[id]!).importingAnimation()
                let rep = imported.rep
                // cursor.7 と 8 のように同じ登録先へ当たる組は、先に来た方だけ残す(resolvedPlan が重複を拒否するため)。
                let names = try CursorCatalog.targets(for: key)
                guard names.allSatisfy({ !usedTargets.contains($0) }) else {
                    skipped.append("\(id)(ほかの識別子と同じ登録先)")
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
            throw CursorKitError.theme("\(file.lastPathComponent) に取り込めるカーソルが無い: \(skipped.joined(separator: ", "))")
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
            guard let n = entry[key] as? NSNumber else { throw CursorKitError.invalidCursor("\(key) が無い") }
            return n.doubleValue
        }
        let size = CGSize(width: try number("PointsWide"), height: try number("PointsHigh"))
        let frameCount = Int(try number("FrameCount"))
        let hotspot = CGPoint(x: try number("HotSpotX"), y: try number("HotSpotY"))
        guard size.width >= 1, size.height >= 1, frameCount >= 1 else {
            throw CursorKitError.invalidCursor("size=\(size) frameCount=\(frameCount) が不正")
        }
        // 静止画にも FrameDuration=1 が入っている。登録形式では静止画の間隔は 0。
        let frameDuration = frameCount > 1 ? try number("FrameDuration") : 0

        var images: [CGImage] = []
        for data in entry["Representations"] as? [Data] ?? [] {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
            for i in 0..<CGImageSourceGetCount(source) {
                if let image = CGImageSourceCreateImageAtIndex(source, i, nil) { images.append(normalizedImage(image)) }
            }
        }
        guard !images.isEmpty else { throw CursorKitError.invalidCursor("画像を読めない") }

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
                throw CursorKitError.invalidCursor("画像の高さ \(largest.height) が \(frameCount) コマで割り切れない")
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

/// 縦に並んだコマを1コマずつ縮小して並べ直す。帯ごと縮小すると隣のコマの端が混ざるため。
func resampleStrip(_ strip: CGImage, frameCount: Int, to frameSize: CGSize) throws -> CGImage {
    let w = Int(frameSize.width.rounded())
    let h = Int(frameSize.height.rounded())
    let sourceHeight = strip.height / frameCount
    guard
        let ctx = CGContext(
            data: nil, width: w, height: h * frameCount, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CursorKitError.io("縮小先の画像を作れない") }
    ctx.interpolationQuality = .high
    for i in 0..<frameCount {
        guard
            let frame = strip.cropping(
                to: CGRect(x: 0, y: i * sourceHeight, width: strip.width, height: sourceHeight))
        else { throw CursorKitError.io("コマ \(i) を切り出せない") }
        // CGContext は下が原点。先頭コマを上に置く。
        ctx.draw(frame, in: CGRect(x: 0, y: (frameCount - 1 - i) * h, width: w, height: h))
    }
    return ctx.makeImage()!
}
