import CursorKit

/// テーマのキーを画面に出すときの名前と並び順。キーの綴りはテーマごとに違ってよい(大文字小文字を区別しない)。
enum CursorRoles {
    struct Group: Identifiable {
        let id: String
        let title: String
        let keys: [String]
    }

    static var groups: [Group] {
        [
            Group(
                id: "basic", title: L10n.text("基本"),
                keys: [
                    "arrow", "ibeam", "pointingHand", "Help", "BusyButClickable", "NotAllowed", "Cross",
                    "ContextualMenu",
                    "IBeamVertical",
                ]),
            Group(
                id: "drag", title: L10n.text("ドラッグ"),
                keys: ["OpenHand", "ClosedHand", "Copy", "MakeAlias", "DisappearingItem", "WindowMove"]),
            Group(
                id: "resize", title: L10n.text("サイズ変更"),
                keys: [
                    "ResizeLeftRight", "ResizeLeft", "ResizeRight", "ResizeUpDown", "ResizeUp", "ResizeDown",
                    "WindowResizeEastWest", "WindowResizeEast", "WindowResizeWest", "WindowResizeNorthSouth",
                    "WindowResizeNorth", "WindowResizeSouth", "WindowResizeNorthWestSouthEast", "WindowResizeNorthWest",
                    "WindowResizeSouthEast", "WindowResizeNorthEastSouthWest", "WindowResizeNorthEast",
                    "WindowResizeSouthWest",
                ]),
            Group(id: "other", title: L10n.text("その他"), keys: ["ZoomIn", "ZoomOut", "Cell", "ScreenshotWindow"]),
        ]
    }

    static var titles: [String: String] {
        [
            "arrow": L10n.text("矢印"), "ibeam": L10n.text("テキスト"), "pointinghand": L10n.text("リンク"),
            "help": L10n.text("ヘルプ"),
            "busybutclickable": L10n.text("処理中"), "notallowed": L10n.text("使用不可"), "cross": L10n.text("精密選択"),
            "contextualmenu": L10n.text("コンテキストメニュー"),
            "ibeamvertical": L10n.text("縦書きテキスト"), "openhand": L10n.text("つかむ(開)"), "closedhand": L10n.text("つかむ(閉)"),
            "copy": L10n.text("コピー"),
            "makealias": L10n.text("エイリアス"), "disappearingitem": L10n.text("削除"), "windowmove": L10n.text("移動"),
            "resizeleftright": L10n.text("左右"), "resizeleft": L10n.text("左"), "resizeright": L10n.text("右"),
            "resizeupdown": L10n.text("上下"),
            "resizeup": L10n.text("上"), "resizedown": L10n.text("下"), "windowresizeeastwest": L10n.text("ウィンドウ 左右"),
            "windowresizeeast": L10n.text("ウィンドウ 右"), "windowresizewest": L10n.text("ウィンドウ 左"),
            "windowresizenorthsouth": L10n.text("ウィンドウ 上下"), "windowresizenorth": L10n.text("ウィンドウ 上"),
            "windowresizesouth": L10n.text("ウィンドウ 下"), "windowresizenorthwestsoutheast": L10n.text("ウィンドウ 斜め ↖↘"),
            "windowresizenorthwest": L10n.text("ウィンドウ 左上"), "windowresizesoutheast": L10n.text("ウィンドウ 右下"),
            "windowresizenortheastsouthwest": L10n.text("ウィンドウ 斜め ↗↙"), "windowresizenortheast": L10n.text("ウィンドウ 右上"),
            "windowresizesouthwest": L10n.text("ウィンドウ 左下"), "zoomin": L10n.text("拡大"), "zoomout": L10n.text("縮小"),
            "cell": L10n.text("セル"),
            "screenshotwindow": L10n.text("スクリーンショット"),
        ]
    }

    /// arrow などの別名や cursor.N も役割名にそろえる(CursorCatalog.targets と同じ解釈)。
    static func canonical(_ key: String) -> String {
        let k = key.lowercased()
        switch k {
        case "arrows", "com.apple.coregraphics.arrow", "com.apple.coregraphics.arrows": return "arrow"
        case "ibeams", "com.apple.coregraphics.ibeam", "com.apple.coregraphics.ibeams": return "ibeam"
        case "link", "hand", "cursor.13", "com.apple.cursor.13": return "pointinghand"
        default: break
        }
        for prefix in ["com.apple.cursor.", "cursor."] where k.hasPrefix(prefix) {
            if let id = Int(k.dropFirst(prefix.count)), let role = CursorCatalog.roleNames[id] {
                return role.lowercased()
            }
        }
        return k
    }

    static func title(for key: String) -> String {
        titles[canonical(key)] ?? key
    }

    /// テーマのキーをグループに振り分ける。表に無いキーは「その他」の末尾に入れる。
    static func grouped(_ keys: [String]) -> [(group: Group, keys: [String])] {
        var remaining = Dictionary(keys.map { (canonical($0), $0) }, uniquingKeysWith: { a, _ in a })
        var result: [(Group, [String])] = []
        for group in groups {
            var found: [String] = []
            for key in group.keys {
                if let original = remaining.removeValue(forKey: key.lowercased()) { found.append(original) }
            }
            if group.id == "other" { found += remaining.values.sorted() }
            if !found.isEmpty { result.append((group, found)) }
        }
        return result
    }

    /// サイドバーや見出しに出す代表のカーソル。
    static func representative(of theme: CursorTheme) -> CursorRep? {
        if let key = theme.cursors.keys.first(where: { canonical($0) == "arrow" }) { return theme.cursors[key] }
        return theme.cursors.keys.sorted().first.flatMap { theme.cursors[$0] }
    }
}
