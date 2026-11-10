import CursorKit

/// テーマのキーを画面に出すときの名前と並び順。キーの綴りはテーマごとに違ってよい(大文字小文字を区別しない)。
enum CursorRoles {
    struct Group: Identifiable {
        let id: String
        let title: String
        let keys: [String]
    }

    static let groups: [Group] = [
        Group(
            id: "basic", title: "基本",
            keys: [
                "arrow", "ibeam", "pointingHand", "Help", "BusyButClickable", "NotAllowed", "Cross", "ContextualMenu",
                "IBeamVertical",
            ]),
        Group(
            id: "drag", title: "ドラッグ",
            keys: ["OpenHand", "ClosedHand", "Copy", "MakeAlias", "DisappearingItem", "WindowMove"]),
        Group(
            id: "resize", title: "サイズ変更",
            keys: [
                "ResizeLeftRight", "ResizeLeft", "ResizeRight", "ResizeUpDown", "ResizeUp", "ResizeDown",
                "WindowResizeEastWest", "WindowResizeEast", "WindowResizeWest", "WindowResizeNorthSouth",
                "WindowResizeNorth", "WindowResizeSouth", "WindowResizeNorthWestSouthEast", "WindowResizeNorthWest",
                "WindowResizeSouthEast", "WindowResizeNorthEastSouthWest", "WindowResizeNorthEast",
                "WindowResizeSouthWest",
            ]),
        Group(id: "other", title: "その他", keys: ["ZoomIn", "ZoomOut", "Cell", "ScreenshotWindow"]),
    ]

    static let titles: [String: String] = [
        "arrow": "矢印", "ibeam": "テキスト", "pointinghand": "リンク", "help": "ヘルプ",
        "busybutclickable": "処理中", "notallowed": "使用不可", "cross": "精密選択", "contextualmenu": "コンテキストメニュー",
        "ibeamvertical": "縦書きテキスト", "openhand": "つかむ(開)", "closedhand": "つかむ(閉)", "copy": "コピー",
        "makealias": "エイリアス", "disappearingitem": "削除", "windowmove": "移動",
        "resizeleftright": "左右", "resizeleft": "左", "resizeright": "右", "resizeupdown": "上下",
        "resizeup": "上", "resizedown": "下", "windowresizeeastwest": "ウィンドウ 左右",
        "windowresizeeast": "ウィンドウ 右", "windowresizewest": "ウィンドウ 左",
        "windowresizenorthsouth": "ウィンドウ 上下", "windowresizenorth": "ウィンドウ 上",
        "windowresizesouth": "ウィンドウ 下", "windowresizenorthwestsoutheast": "ウィンドウ 斜め ↖↘",
        "windowresizenorthwest": "ウィンドウ 左上", "windowresizesoutheast": "ウィンドウ 右下",
        "windowresizenortheastsouthwest": "ウィンドウ 斜め ↗↙", "windowresizenortheast": "ウィンドウ 右上",
        "windowresizesouthwest": "ウィンドウ 左下", "zoomin": "拡大", "zoomout": "縮小", "cell": "セル",
        "screenshotwindow": "スクリーンショット",
    ]

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
