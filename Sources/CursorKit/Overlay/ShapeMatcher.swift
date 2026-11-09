import AppKit
import CryptoKit

/// いま表示されているカーソル(NSCursor.currentSystem)が、どの登録名の標準画像かを引く。
/// 照合は大きさ・hotspot と、最大解像度の画像を sRGB RGBA8 に描き直した画素のハッシュで行う。
@MainActor
public final class ShapeMatcher {
    /// 照合キー → 登録名(com.apple.coregraphics.ArrowS / com.apple.cursor.N)
    private(set) var table: [String: String] = [:]

    public init() {}

    public var count: Int { table.count }

    /// 標準画像を照合表に加える。同じキーが既にあれば先に入れたものを残す。
    func add(name: String, rep: CursorRep) {
        guard let image = rep.images.max(by: { $0.width < $1.width }) else { return }
        let key = Self.key(size: rep.size, hotspot: rep.hotspot, image: image)
        if table[key] == nil { table[key] = name }
    }

    /// AppKit のファクトリが返す標準画像を、-_coreCursorType の番号で com.apple.cursor.N に対応づけて加える。
    /// CGS の読み取りもスナップショットも無いときの最後の照合元。arrow / IBeam はプロセスによって画像が空なので使わない。
    func addAppKitFactories() {
        let typeSelector = NSSelectorFromString("_coreCursorType")
        for cursor in Self.factoryCursors() where cursor.responds(to: typeSelector) {
            typealias TypeFn = @convention(c) (AnyObject, Selector) -> Int
            let type = unsafeBitCast(cursor.method(for: typeSelector), to: TypeFn.self)(cursor, typeSelector)
            guard CursorCatalog.coreCursorIDs.contains(type), let image = Self.largestImage(cursor.image) else {
                continue
            }
            let key = Self.key(size: cursor.image.size, hotspot: cursor.hotSpot, image: image)
            if table[key] == nil { table[key] = CursorCatalog.coreCursorPrefix + String(type) }
        }
    }

    func name(for cursor: NSCursor) -> (name: String?, key: String) {
        guard let image = Self.largestImage(cursor.image) else { return (nil, "noimage") }
        let key = Self.key(size: cursor.image.size, hotspot: cursor.hotSpot, image: image)
        return (table[key], key)
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
        if #available(macOS 15.0, *) { cursors += [.zoomIn, .zoomOut, .columnResize, .rowResize] }
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
