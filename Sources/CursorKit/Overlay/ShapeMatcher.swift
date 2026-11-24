import AppKit
import CryptoKit

/// いま表示されているカーソル(NSCursor.currentSystem)が、どの登録名の標準画像かを引く。
/// 照合は大きさ・hotspot と、画像を sRGB RGBA8 に描き直した画素のハッシュで行う。
@MainActor
public final class ShapeMatcher {
    /// 照合キー → 登録名(com.apple.coregraphics.ArrowS / com.apple.cursor.N)
    private var table: [String: Set<String>] = [:]

    public init() {}

    public var count: Int { table.count }

    func add(name: String, rep: CursorRep) {
        for image in rep.images {
            let key = Self.key(size: rep.size, hotspot: rep.hotspot, image: image)
            table[key, default: []].insert(name)
        }
    }

    /// AppKit のファクトリが返す標準画像を、-_coreCursorType の番号で com.apple.cursor.N に対応づけて加える。
    /// CGS の読み取りやスナップショットで欠けている画像も照合できるようにする。
    func addAppKitFactories() {
        add(cursor: .arrow, name: CursorCatalog.coreGraphicsPrefix + "ArrowS")
        add(cursor: .iBeam, name: CursorCatalog.coreGraphicsPrefix + "IBeamS")
        let typeSelector = NSSelectorFromString("_coreCursorType")
        for cursor in Self.factoryCursors() where cursor.responds(to: typeSelector) {
            typealias TypeFn = @convention(c) (AnyObject, Selector) -> Int
            let type = unsafeBitCast(cursor.method(for: typeSelector), to: TypeFn.self)(cursor, typeSelector)
            guard CursorCatalog.coreCursorIDs.contains(type) else { continue }
            add(cursor: cursor, name: CursorCatalog.coreCursorPrefix + String(type))
        }
    }

    private func add(cursor: NSCursor, name: String) {
        let image = cursor.image
        let bitmaps = image.representations.compactMap { ($0 as? NSBitmapImageRep)?.cgImage }
        let variants = bitmaps.isEmpty ? Self.largestImage(image).map { [$0] } ?? [] : bitmaps
        // 一部のプロセスでは矢印や I ビームのファクトリから空の画像が返る。
        for variant in variants where variant.hasVisibleCursorPixels {
            let key = Self.key(size: image.size, hotspot: cursor.hotSpot, image: variant)
            table[key, default: []].insert(name)
        }
    }

    func names(for cursor: NSCursor) -> (names: Set<String>, key: String) {
        guard let image = Self.largestImage(cursor.image) else { return ([], "noimage") }
        let key = Self.key(size: cursor.image.size, hotspot: cursor.hotSpot, image: image)
        return (table[key, default: []], key)
    }

    static func themedName(for names: Set<String>, hashes: [String: String]) -> String? {
        // currentSystem は同じ画像を使う役割を区別する番号を返さない。
        guard let first = names.min(), let hash = hashes[first],
            names.allSatisfy({ hashes[$0] == hash })
        else { return nil }
        return first
    }

    static func largestImage(_ image: NSImage) -> CGImage? {
        let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        if let best = reps.max(by: { $0.pixelsWide < $1.pixelsWide }) { return best.cgImage }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func key(size: CGSize, hotspot: CGPoint, image: CGImage) -> String {
        var hasher = SHA256()
        hasher.update(
            data: Data(
                "\(Int(size.width))x\(Int(size.height));\(Int(hotspot.x)),\(Int(hotspot.y));\(image.width)x\(image.height)"
                    .utf8))
        hasher.update(data: rgbaBytes(image))
        return hasher.finalize().prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// Phase 3.5 で呼んでも安全だと確かめたファクトリだけを使う(例: _moveCursor は例外で落ちる)。
    static func factoryCursors() -> [NSCursor] {
        var cursors: [NSCursor] = [
            .dragLink, .operationNotAllowed, .dragCopy, .closedHand, .openHand, .pointingHand, .resizeLeft,
            .resizeRight, .resizeLeftRight, .resizeUp, .resizeDown, .resizeUpDown, .crosshair, .contextualMenu,
            .disappearingItem, .iBeamCursorForVerticalLayout,
        ]
        if #available(macOS 15.0, *) {
            let positions: [NSCursor.FrameResizePosition] = [
                .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left, .topLeft,
            ]
            let directions: [NSCursor.FrameResizeDirection.Set] = [.inward, .outward, .all]
            cursors += positions.flatMap { position in
                directions.map { NSCursor.frameResize(position: position, directions: $0) }
            }
            cursors += [
                .zoomIn, .zoomOut, .columnResize, .rowResize, .columnResize(directions: .left),
                .columnResize(directions: .right), .rowResize(directions: .up), .rowResize(directions: .down),
            ]
        }
        let privateNames =
            ["busyButClickableCursor", "_helpCursor"]
            + [
                "East", "EastWest", "NorthEast", "NorthEastSouthWest", "North", "NorthSouth", "NorthWest",
                "NorthWestSouthEast", "SouthEast", "South", "SouthWest", "West",
            ].map { "_windowResize\($0)Cursor" }
        for name in privateNames {
            let sel = NSSelectorFromString(name)
            guard NSCursor.responds(to: sel),
                let c = (NSCursor.self as AnyObject).perform(sel)?.takeUnretainedValue() as? NSCursor
            else { continue }
            cursors.append(c)
        }
        return cursors
    }
}
