import Foundation

/// macOS 27.2 で確認した識別子の表(docs/PHASE0.md)。
/// OS に識別子を列挙する手段が無いため固定表を持つ。新しい名前は CGSCursorNameForSystemCursor の
/// 表との差分として診断に出し、表に無い名前は標準のまま残す(縮退)。
public enum CursorCatalog {
    public static let coreGraphicsPrefix = "com.apple.coregraphics."
    public static let coreCursorPrefix = "com.apple.cursor."

    /// スナップショット・復元の対象。
    /// Arrow / IBeam は読み戻すと ArrowS / IBeamS の内容が返り、登録しても表示に効かないので含めない。
    /// GlobalCurrent / ConnectionCurrent は「いま表示中のカーソル」を返す動的な値なので含めない。
    public static let snapshotNames: [String] =
        ["ArrowS", "IBeamS", "Move", "Wait", "IBeamXOR", "Alias", "Copy", "ArrowCtx", "Empty"].map {
            coreGraphicsPrefix + $0
        } + coreCursorIDs.map { coreCursorPrefix + String($0) }

    /// com.apple.cursor.N の N。それ以外の名前は nil。
    public static func coreCursorID(of name: String) -> Int? {
        guard name.hasPrefix(coreCursorPrefix) else { return nil }
        return Int(name.dropFirst(coreCursorPrefix.count))
    }

    /// CoreCursorUnregisterAll のループ上限 44 と一致する。
    public static let coreCursorIDs = Array(0...43)

    /// CGSCursorNameForSystemCursor の表(macOS 27.2)。これと違えば OS 側で識別子が変わった兆候。
    public static let knownSystemCursorTable: [Int32: String] = [
        0: "Arrow", 1: "IBeam", 2: "IBeamXOR", 3: "Alias", 4: "Copy", 5: "Move", 6: "ArrowCtx",
        7: "Wait", 8: "Empty", 100: "ArrowS", 101: "IBeamS",
    ].mapValues { coreGraphicsPrefix + $0 }

    /// CoreCursor ID → 役割名。AccessibilityFoundation の +[_AXFMouseCursorGenerator _nameForCursor:] が返す
    /// com.apple.accessibility.cursor.<役割名> から取った(macOS 27.2)。目視では未確認。
    public static let roleNames: [Int: String] = [
        2: "MakeAlias", 3: "NotAllowed", 5: "Copy", 9: "ScreenshotWindow", 11: "ClosedHand", 12: "OpenHand",
        17: "ResizeLeft", 18: "ResizeRight", 19: "ResizeLeftRight", 20: "Cross", 21: "ResizeUp", 22: "ResizeDown",
        23: "ResizeUpDown", 26: "IBeamVertical", 27: "WindowResizeEast", 28: "WindowResizeEastWest",
        29: "WindowResizeNorthEast", 30: "WindowResizeNorthEastSouthWest", 31: "WindowResizeNorth",
        32: "WindowResizeNorthSouth", 33: "WindowResizeNorthWest", 34: "WindowResizeNorthWestSouthEast",
        35: "WindowResizeSouthEast", 36: "WindowResizeSouth", 37: "WindowResizeSouthWest", 38: "WindowResizeWest",
        39: "WindowMove", 41: "Cell",
    ]

    /// テーマのキー → 実際に登録する名前の集合。
    /// arrow / ibeam / pointingHand は目視で確かめた。roleNames の名前と cursor.N も受け付ける。
    public static func targets(for key: String) throws -> [String] {
        let k = key.lowercased()
        switch k {
        case "arrow", "arrows", "com.apple.coregraphics.arrow", "com.apple.coregraphics.arrows":
            return [coreGraphicsPrefix + "ArrowS"]
        case "ibeam", "ibeams", "com.apple.coregraphics.ibeam", "com.apple.coregraphics.ibeams":
            return [coreGraphicsPrefix + "IBeamS"]
        case "pointinghand", "link", "hand":
            return [coreCursorPrefix + "13"]
        default:
            break
        }
        if let id = roleNames.first(where: { $0.value.lowercased() == k })?.key {
            return try targets(for: "cursor.\(id)")
        }
        var idString = k
        for prefix in ["com.apple.cursor.", "cursor."] where idString.hasPrefix(prefix) {
            idString = String(idString.dropFirst(prefix.count))
        }
        guard let id = Int(idString), coreCursorIDs.contains(id) else {
            throw CursorKitError.unknownCursorKey(key)
        }
        // 標準画像がピクセル単位で同一の組。テーマ側で片方だけ定義されても両方に当てる。
        let aliasGroups: [[Int]] = [[7, 8], [9, 10]]
        let group = aliasGroups.first { $0.contains(id) } ?? [id]
        return group.map { coreCursorPrefix + String($0) }
    }
}
