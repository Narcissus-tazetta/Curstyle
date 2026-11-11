import CoreGraphics
import Foundation
import ImageIO

/// Windows のカーソルテーマ(.ani / .cur を役割名のファイルで並べたフォルダ)を CursorTheme に変換する。
public enum WindowsCursorImporter {
    private static let arrowTargets = ["arrow"]
    private static let textTargets = ["ibeam"]
    private static let linkTargets = ["pointingHand"]
    private static let helpTargets = ["Help"]
    private static let workingTargets = ["BusyButClickable"]
    private static let unavailableTargets = ["NotAllowed"]
    private static let precisionTargets = ["Cross"]
    private static let moveTargets = ["WindowMove"]
    private static let horizontalTargets = [
        "ResizeLeftRight", "ResizeLeft", "ResizeRight", "WindowResizeEastWest", "WindowResizeEast",
        "WindowResizeWest",
    ]
    private static let verticalTargets = [
        "ResizeUpDown", "ResizeUp", "ResizeDown", "WindowResizeNorthSouth", "WindowResizeNorth",
        "WindowResizeSouth",
    ]
    private static let diagonal1Targets = [
        "WindowResizeNorthWestSouthEast", "WindowResizeNorthWest", "WindowResizeSouthEast",
    ]
    private static let diagonal2Targets = [
        "WindowResizeNorthEastSouthWest", "WindowResizeNorthEast", "WindowResizeSouthWest",
    ]
    private static let copyTargets = ["Copy"]
    private static let aliasTargets = ["MakeAlias"]
    private static let contextMenuTargets = ["ContextualMenu"]
    private static let verticalTextTargets = ["IBeamVertical"]
    private static let openHandTargets = ["OpenHand"]
    private static let closedHandTargets = ["ClosedHand"]
    private static let zoomInTargets = ["ZoomIn"]
    private static let zoomOutTargets = ["ZoomOut"]
    private static let cellTargets = ["Cell"]

    /// ファイル名(拡張子なし・小文字)→ 当てる Curstyle のキー。
    /// macOS 側の対応物が無い役割(Busy / Alternate / Handwriting / Pin / Person)は含めず、標準のまま残す。
    /// Busy(Wait)は WindowServer が自前で描くスピナーで、カーソル画像の差し替え対象かどうか未確認。
    public static let roleMap: [String: [String]] = buildRoleMap()

    public struct Result {
        public var theme: CursorTheme
        public var skippedFiles: [String]
        public var adjustments: [String]
    }

    /// pixelsPerPoint: 画像1枚の何ピクセルを1ptとみなすか。Windows の 32px を Retina で 32px のまま見せるなら 2。
    public static func importTheme(directory: URL, name: String, pixelsPerPoint: Int) throws -> Result {
        guard (1...4).contains(pixelsPerPoint) else { throw CursorKitError.theme("--scale は 1〜4") }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var cursors: [String: CursorRep] = [:]
        var skipped: [String] = []
        var adjustments: [String] = []
        let infMap = loadINFRoleMap(for: directory)

        // 同じ役割に .ani と .cur があれば .ani(アニメ)を優先する。
        // .cur / .ani 以外(install.inf など)を混ぜると比較が推移律を満たさず、採用されるファイルが不定になる。
        let sortedFiles = files.filter { ["ani", "cur"].contains($0.pathExtension.lowercased()) }.sorted {
            let ext0 = $0.pathExtension.lowercased()
            let ext1 = $1.pathExtension.lowercased()
            if ext0 != ext1 {
                return ext0 == "ani"
            }
            return $0.lastPathComponent < $1.lastPathComponent
        }

        for file in sortedFiles {
            let ext = file.pathExtension.lowercased()
            let fileName = file.lastPathComponent.lowercased()
            let stem = file.deletingPathExtension().lastPathComponent
            guard let keys = infMap[fileName] ?? roleKeys(for: stem) else {
                skipped.append(file.lastPathComponent)
                continue
            }
            guard keys.allSatisfy({ cursors[$0] == nil }) else { continue }
            let rep: CursorRep
            do {
                let imported = try cursorRep(
                    from: Data(contentsOf: file), isAnimated: ext == "ani", pixelsPerPoint: pixelsPerPoint
                ).importingAnimation()
                rep = imported.rep
                if let adjustment = imported.adjustment {
                    adjustments.append("\(file.lastPathComponent): \(adjustment)")
                }
            } catch {
                throw CursorKitError.theme("\(file.lastPathComponent): \(error)")
            }
            for key in keys { cursors[key] = rep }
        }
        guard !cursors.isEmpty else { throw CursorKitError.theme("\(directory.path) に取り込める .ani / .cur が無い") }
        return Result(theme: CursorTheme(name: name, cursors: cursors), skippedFiles: skipped, adjustments: adjustments)
    }

    // MARK: - 役割判定

    private static let tokenDelimiterCharacters = "-_.\t\u{3000}~+ "
    private static let tokenDelimiters = CharacterSet(charactersIn: tokenDelimiterCharacters)

    public static func roleKeys(for stem: String) -> [String]? {
        let lower = stem.lowercased()
        if let keys = roleMap[lower] { return keys }

        let cleaned = lower.filter { !tokenDelimiterCharacters.contains($0) }
        if let keys = roleMap[cleaned] { return keys }

        var normalized = lower
        var changed = true
        while changed {
            changed = false
            if let withoutParen = stripParenthesized(normalized) {
                normalized = withoutParen
                changed = true
            }
            if let withoutPrefix = stripLeadingIndex(normalized) {
                normalized = withoutPrefix
                changed = true
            }
            if let withoutAero = stripAeroPrefix(normalized) {
                normalized = withoutAero
                changed = true
            }
            if let withoutSuffix = stripVariantSuffix(normalized) {
                normalized = withoutSuffix
                changed = true
            }
        }
        if normalized != lower {
            if let keys = roleMap[normalized] { return keys }
            let normCleaned = normalized.filter { !tokenDelimiterCharacters.contains($0) }
            if let keys = roleMap[normCleaned] { return keys }
        }

        let tokens = lower.components(separatedBy: tokenDelimiters)
            .filter { !$0.isEmpty }
        if let last = tokens.last, let keys = roleMap[last] {
            return keys
        }
        for token in tokens.reversed() {
            if let keys = roleMap[token] { return keys }
        }

        let normTokens = normalized.components(separatedBy: tokenDelimiters)
            .filter { !$0.isEmpty }
        if let last = normTokens.last, let keys = roleMap[last] {
            return keys
        }
        for token in normTokens.reversed() {
            if let keys = roleMap[token] { return keys }
        }

        return matchKeyword(cleaned) ?? matchKeyword(normalized.filter { !tokenDelimiterCharacters.contains($0) })
    }

    private static func stripParenthesized(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: tokenDelimiters)
        guard trimmed.hasSuffix(")") else { return nil }
        guard let openParen = trimmed.lastIndex(of: "(") else { return nil }
        let stripped = String(trimmed[..<openParen]).trimmingCharacters(in: tokenDelimiters)
        return stripped.isEmpty ? nil : stripped
    }

    private static func stripAeroPrefix(_ s: String) -> String? {
        for prefix in ["aero_", "aero-", "aero "] {
            if s.hasPrefix(prefix) {
                let stripped = String(s.dropFirst(prefix.count)).trimmingCharacters(in: tokenDelimiters)
                return stripped.isEmpty ? nil : stripped
            }
        }
        return nil
    }

    private static func stripLeadingIndex(_ s: String) -> String? {
        guard let first = s.first, first.isNumber else { return nil }
        var index = s.startIndex
        while index < s.endIndex, s[index].isNumber {
            index = s.index(after: index)
        }
        guard index < s.endIndex, tokenDelimiterCharacters.contains(s[index]) else { return nil }
        while index < s.endIndex, tokenDelimiterCharacters.contains(s[index]) {
            index = s.index(after: index)
        }
        let rest = String(s[index...])
        return rest.isEmpty ? nil : rest
    }

    private static let knownSuffixes: [String] = [
        "-extralarge", "_extralarge", "-noshadow", "_noshadow", "-diagonal", "_diagonal",
        "-regular", "_regular", "-static", "_static", "-shadow", "_shadow",
        "-xlarge", "_xlarge", "-large", "_large", "-small", "_small",
        "-black", "_black", "-white", "_white", "-green", "_green", "-light", "_light",
        "-mini", "_mini", "mini", "-huge", "_huge", "-dark", "_dark", "-blue", "_blue",
        "-256", "_256", "-128", "_128", "-big", "_big", "-alt", "_alt", "-red", "_red",
        "-fhd", "_fhd", "-ani", "_ani", "-cur", "_cur",
        "-96", "_96", "-64", "_64", "-48", "_48", "-32", "_32",
        "-4k", "_4k", "-hd", "_hd",
        "-1x", "_1x", "-2x", "_2x", "-3x", "_3x", "-4x", "_4x",
        "-v1", "_v1", "-v2", "_v2",
        "-rl", "_rl", "-rm", "_rm", "-il", "_il", "-im", "_im",
        "-xl", "_xl", "-xs", "_xs",
        "-l", "_l", "-m", "_m", "-s", "_s",
        "-r", "_r", "-i", "_i",
    ]

    private static func stripVariantSuffix(_ s: String) -> String? {
        for suffix in knownSuffixes where s.hasSuffix(suffix) {
            let stripped = String(s.dropLast(suffix.count)).trimmingCharacters(in: tokenDelimiters)
            if !stripped.isEmpty { return stripped }
        }
        return nil
    }

    private static func matchKeyword(_ cleaned: String) -> [String]? {
        for kw in ["diagonalresize1", "sizenwse", "diagonal1", "dgn1", "dng1", "nwseresize", "sizebdiag", "nwse", "diag1", "resize1", "topleftcorner", "bottomrightcorner", "nwresize", "seresize", "aeronwse", "resizedi1", "diresize1", "stretchtlbr", "diagonalbackslash", "backslashresize"] {
            if cleaned.contains(kw) { return diagonal1Targets }
        }
        for kw in ["diagonalresize2", "sizenesw", "diagonal2", "dgn2", "dng2", "neswresize", "sizefdiag", "nesw", "diag2", "resize2", "toprightcorner", "bottomleftcorner", "neresize", "swresize", "aeronesw", "resizedi2", "diresize2", "stretchbltr", "diagonalfrontslash", "frontslashresize", "slashresize"] {
            if cleaned.contains(kw) { return diagonal2Targets }
        }
        for kw in ["horizontalresize", "sizewe", "sizeew", "resizeleftright", "horizontal", "horz", "horiz", "weresize", "ewresize", "eresize", "wresize", "leftside", "rightside", "colresize", "splith", "aeroew", "aerowe", "eastwest", "splithorz", "hdoublearrow"] {
            if cleaned.contains(kw) { return horizontalTargets }
        }
        for kw in ["verticalresize", "sizens", "resizeupdown", "vertical", "vert", "nsresize", "nresize", "sresize", "topside", "bottomside", "rowresize", "splitv", "aerons", "northsouth", "splitvert", "vdoublearrow"] {
            if cleaned.contains(kw) { return verticalTargets }
        }
        for kw in ["workinginbackground", "workingbackground", "appstarting", "working", "halfbusy", "progress", "loading", "pointerwithspinner", "arrowwithspinner", "pointerspinner", "arrowspinner", "aeroworking", "lappstrt", "appstart", "arrowwait", "workinginbg"] {
            if cleaned.contains(kw) { return workingTargets }
        }
        for kw in ["notallowed", "unavailable", "unavailiable", "unavralible", "forbidden", "nodrop", "crossedcircle", "dndnone", "dndnodrop", "aerounavail", "notallowed", "prohibited", "noentry", "cantdrop"] {
            if cleaned.contains(kw) { return unavailableTargets }
        }
        for kw in ["precisionselect", "crosshair", "areaselect", "precision", "precise", "tcross", "aerocross", "precisionhair", "bullseye"] {
            if cleaned.contains(kw) { return precisionTargets }
        }
        for kw in ["sizeall", "allscroll", "windowmove", "dndmove", "aeromove", "fourway", "arrowsall"] {
            if cleaned.contains(kw) { return moveTargets }
        }
        for kw in ["helpselect", "questionarrow", "whatsthis", "aerohelpsel", "questionmark", "helparrow"] {
            if cleaned.contains(kw) { return helpTargets }
        }
        for kw in ["textselect", "ibeam", "beam", "xterm", "aerobeam", "textcursor", "ibar"] {
            if cleaned.contains(kw) { return textTargets }
        }
        for kw in ["pointinghand", "linkselect", "linkexp", "aerolink", "pointingfinger", "handpoint", "weblink"] {
            if cleaned.contains(kw) { return linkTargets }
        }
        for kw in ["normalselect", "topleftarrow", "leftptr", "rightptr", "cursor", "normal", "aeroarrow", "maincursor"] {
            if cleaned.contains(kw) { return arrowTargets }
        }
        return nil
    }

    private static func buildRoleMap() -> [String: [String]] {
        var map: [String: [String]] = [:]
        func register(_ words: [String], _ targets: [String]) {
            for word in words {
                let lower = word.lowercased()
                map[lower] = targets
                let noSep = lower.filter { !tokenDelimiterCharacters.contains($0) }
                map[noSep] = targets
                map[lower.replacingOccurrences(of: "-", with: "_")] = targets
                map[lower.replacingOccurrences(of: "-", with: " ")] = targets
                map[lower.replacingOccurrences(of: "_", with: "-")] = targets
                map[lower.replacingOccurrences(of: "_", with: " ")] = targets
                map[lower.replacingOccurrences(of: " ", with: "-")] = targets
                map[lower.replacingOccurrences(of: " ", with: "_")] = targets
            }
        }

        register([
            "normal", "arrow", "pointer", "default", "normalselect", "normal-select",
            "arrow-select", "arrow-cursor", "arrow-pointer", "left_ptr", "center_ptr", "right_ptr",
            "top_left_arrow", "base", "main", "standard", "std", "std-arrow", "cursor",
            "larrow", "marrow", "sarrow", "rarrow",
            "aero_arrow", "aero-arrow", "arrow_r", "arrow-r", "pointer_r", "pointer-r",
            "main-cursor", "main_cursor", "standard-cursor", "standard_cursor", "std-cursor", "std_cursor",
            "arro", "3dgarro", "3dwarro",
            "通常", "通常の選択", "矢印",
        ], arrowTargets)

        register([
            "text", "ibeam", "beam", "xterm", "textselect", "text-select", "bar",
            "i-beam", "i_beam", "edit", "caret",
            "libeam", "mibeam", "sibeam",
            "aero_beam", "aero-beam", "beam_r", "beam-r", "i-bar", "i_bar", "ibar",
            "text-cursor", "text_cursor",
            "テキスト", "テキスト選択",
        ], textTargets)

        register([
            "link", "pointinghand", "pointing-hand", "hand", "hand1", "hand2", "linkselect",
            "link-select", "linkexp", "tap", "hyperlink", "finger", "pointer-hand", "point",
            "lhand", "mhand", "shand",
            "aero_link", "aero-link", "hand_r", "hand-r", "link_r", "link-r",
            "pointing-finger", "pointing_finger", "pointingfinger", "pointing",
            "hand-point", "hand_point", "handpoint", "hand-pointing", "hand_pointing", "handpointing",
            "web-link", "web_link", "weblink",
            "リンク", "リンク選択", "リンクの選択",
        ], linkTargets)

        register([
            "help", "helpselect", "help-select", "helpsel", "left_ptr_help",
            "question_arrow", "whats_this", "whatsthis", "question", "help-arrow", "questionmark",
            "lhelp", "mhelp", "shelp",
            "aero_helpsel", "aero-helpsel", "helpsel_r", "helpsel-r", "help_r", "help-r",
            "help_arrow", "help-arrow", "helparrow", "question-arrow", "question_arrow", "question_mark", "question-mark",
            "ヘルプ", "ヘルプの選択", "質問",
        ], helpTargets)

        register([
            "working", "work", "appstarting", "progress", "loading", "load", "background",
            "workinginbackground", "working-in-background", "working_background", "app-starting",
            "half-busy", "halfbusy", "left_ptr_watch", "busyclickable", "busy-clickable",
            "spinner", "busy-arrow",
            "pointer-with-spinner", "pointer_with_spinner", "pointer with spinner",
            "arrow-with-spinner", "arrow_with_spinner", "arrow with spinner",
            "pointer-spinner", "pointer_spinner", "pointer spinner",
            "arrow-spinner", "arrow_spinner", "arrow spinner",
            "pointer-watch", "pointer_watch", "pointer watch",
            "arrow-watch", "arrow_watch", "arrow watch",
            "lappstrt", "mappstrt", "sappstrt", "appstart", "apst", "appstar", "handapst",
            "aero_working", "aero-working", "working_r", "working-r",
            "working-in-bg", "working_in_bg", "working-bg", "working_bg", "workbg",
            "arrow-wait", "arrow_wait", "counter",
            "バックグラウンド", "バックグラウンド作業中", "バックグラウンドで作業中", "作業中",
        ], workingTargets)

        register([
            "unavailable", "unavailiable", "unavralible", "unavail", "notallowed", "not-allowed",
            "forbidden", "no", "no-drop", "nodrop", "block", "circle", "crossed_circle",
            "disabled", "stop", "dnd-none", "dnd_none", "dnd-no-drop", "dnd_no_drop", "dnd-nodrop",
            "cancel", "denied", "not-available",
            "lnodrop", "mnodrop", "snodrop",
            "aero_unavail", "aero-unavail", "unavail_r", "unavail-r", "no_r", "no-r",
            "not_allowed", "not-allowed", "not allowed",
            "prohibited", "banned", "no-entry", "no_entry", "noentry", "cant-drop", "cant_drop", "cantdrop",
            "3dgno", "3dwno", "handno",
            "利用不可", "選択不可", "禁止",
        ], unavailableTargets)

        register([
            "precision", "cross", "crosshair", "tcross", "areaselect", "area-select",
            "precise", "target", "precisionselect", "precision-select", "plus", "aim", "reticle",
            "lcross", "mcross", "scross", "hcross",
            "aero_cross", "aero-cross", "cross_r", "cross-r",
            "cross_hair", "cross-hair", "precisionhair", "precision-hair",
            "sight", "scope", "bullseye",
            "精密選択", "領域選択", "十字",
        ], precisionTargets)

        register([
            "move", "sizeall", "size_all", "size-all", "all-scroll", "all_scroll",
            "allscroll", "fleur", "pan", "arrows_all", "windowmove", "window-move",
            "dnd-move", "dnd_move", "drag",
            "lmove", "mmove", "smove", "hmove", "3dgmove", "3dsmove", "3dwmove",
            "aero_move", "aero-move", "move_r", "move-r", "size_all_r", "size-all-r",
            "four-way", "four_way", "fourway", "4way", "4-way", "4_way", "arrows-all", "arrows_all", "arrowsall",
            "移動",
        ], moveTargets)

        register([
            "horizontal", "horz", "sizewe", "size_we", "size-we", "sizeew", "size_ew",
            "size-ew", "we", "ew", "we-resize", "ew-resize", "h_double_arrow",
            "sb_h_double_arrow", "size_hor", "size-hor", "split_h", "split-h", "col-resize",
            "horizontalresize", "horizontal-resize", "resizeleftright", "resizewe",
            "e-resize", "w-resize", "east-resize", "west-resize",
            "left_side", "right_side", "left-side", "right-side",
            "size_left", "size_right", "size-left", "size-right",
            "h-resize", "hresize",
            "lwe", "mwe", "swe", "we_r", "we-r", "ew_r", "ew-r",
            "aero_ew", "aero-ew", "aero_we", "aero-we",
            "size4", "size4_r", "size4-r", "size_4", "size-4",
            "size_horz", "size-horz", "sizehorz",
            "horiz", "horiz-resize", "horiz_resize",
            "east-west", "east_west", "eastwest", "west-east", "west_east", "westeast",
            "h-double-arrow", "h_double_arrow", "hdoublearrow", "split-horiz", "split_horiz", "splithorz",
            "3dgwe", "3dwwe", "hwe", "handwe",
            "左右に拡大・縮小", "左右に拡大", "水平に拡大・縮小", "水平", "左右",
        ], horizontalTargets)

        register([
            "vertical", "vert", "sizens", "size_ns", "size-ns", "ns", "ns-resize",
            "v_double_arrow", "sb_v_double_arrow", "size_ver", "size-ver", "split_v", "split-v",
            "row-resize", "verticalresize", "vertical-resize", "resizeupdown", "resizens",
            "n-resize", "s-resize", "north-resize", "south-resize",
            "top_side", "bottom_side", "top-side", "bottom-side",
            "size_up", "size_down", "size-up", "size-down",
            "v-resize", "vresize",
            "lns", "mns", "sns", "ns_r", "ns-r",
            "aero_ns", "aero-ns",
            "size3", "size3_r", "size3-r", "size_3", "size-3",
            "size_vert", "size-vert", "sizevert",
            "north-south", "north_south", "northsouth", "south-north", "south_north", "southnorth",
            "v-double-arrow", "v_double_arrow", "vdoublearrow", "split-vert", "split_vert", "splitvert",
            "3dgns", "3dsns", "3dwns", "hns", "handns",
            "上下に拡大・縮小", "上下に拡大", "垂直に拡大・縮小", "垂直", "上下",
        ], verticalTargets)

        register([
            "diagonal1", "dgn1", "dng1", "sizenwse", "size_nwse", "size-nwse", "nwse",
            "nwse-resize", "size-bdiag", "size_bdiag", "bdiag", "diagonal-1", "diagonalresize1",
            "diagonal-resize-1", "resizediag1", "diag1", "windowresizenorthwestsoutheast",
            "resize_1", "resize-1", "resize1", "nw-resize", "se-resize",
            "top_left_corner", "bottom_right_corner", "top-left-corner", "bottom-right-corner",
            "size_nw", "size_se", "size-nw", "size-se", "c-resize",
            "lnwse", "mnwse", "snwse", "nwse_r", "nwse-r",
            "aero_nwse", "aero-nwse",
            "size2", "size2_r", "size2-r", "size_2", "size-2",
            "resize_di_1", "resize-di-1", "resizedi1", "di-resize-1", "diresize1",
            "stretch_tl_br", "stretch-tl-br", "stretchtlbr",
            "diagonal-resize-backslash", "diagonal_resize_backslash", "diagonal-backslash", "diagonal_backslash", "backslash-resize", "backslash_resize",
            "nw-se", "nw_se", "diag_1", "diagonal_1",
            "斜めに拡大・縮小1", "斜めに拡大1", "右下がりに拡大・縮小", "右下がり",
        ], diagonal1Targets)

        register([
            "diagonal2", "dgn2", "dng2", "sizenesw", "size_nesw", "size-nesw", "nesw",
            "nesw-resize", "size-fdiag", "size_fdiag", "fdiag", "diagonal-2", "diagonalresize2",
            "diagonal-resize-2", "resizediag2", "diag2", "windowresizenortheastsouthwest",
            "resize_2", "resize-2", "resize2", "ne-resize", "sw-resize",
            "top_right_corner", "bottom_left_corner", "top-right-corner", "bottom-left-corner",
            "size_ne", "size_sw", "size-ne", "size-sw", "d-resize",
            "lnesw", "mnesw", "snesw", "nesw_r", "nesw-r",
            "aero_nesw", "aero-nesw",
            "size1", "size1_r", "size1-r", "size_1", "size-1",
            "resize_di_2", "resize-di-2", "resizedi2", "di-resize-2", "diresize2",
            "stretch_bl_tr", "stretch-bl-tr", "stretchbltr",
            "diagonal-resize-frontslash", "diagonal_resize_frontslash", "diagonal-frontslash", "diagonal_frontslash", "frontslash-resize", "frontslash_resize", "slash-resize", "slash_resize",
            "ne-sw", "ne_sw", "diag_2", "diagonal_2",
            "斜めに拡大・縮小2", "斜めに拡大2", "右上がりに拡大・縮小", "右上がり",
        ], diagonal2Targets)

        register(["copy", "dnd-copy", "dnd_copy", "コピー"], copyTargets)
        register(["alias", "makealias", "dnd-link", "dnd_link", "エイリアス"], aliasTargets)
        register(["context-menu", "context_menu", "contextmenu", "contextualmenu", "コンテキストメニュー"], contextMenuTargets)
        register(["vertical-text", "vertical_text", "verticaltext", "ibeamvertical", "縦書きテキスト"], verticalTextTargets)
        register(["openhand", "open-hand", "open_hand", "grab", "つかむ(開)"], openHandTargets)
        register(["closedhand", "closed-hand", "closed_hand", "closehand", "grabbing", "つかむ(閉)"], closedHandTargets)
        register(["zoom-in", "zoom_in", "zoomin", "拡大"], zoomInTargets)
        register(["zoom-out", "zoom_out", "zoomout", "縮小"], zoomOutTargets)
        register(["cell", "セル"], cellTargets)

        return map
    }

    // MARK: - INF 解析

    static func loadINFRoleMap(for directory: URL) -> [String: [String]] {
        let fm = FileManager.default
        var candidateURLs: [URL] = []
        if let directFiles = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            candidateURLs.append(contentsOf: directFiles.filter { $0.pathExtension.lowercased() == "inf" })
        }
        // 親フォルダの INF は、別テーマの INF を拾わないよう自フォルダに INF が無いときだけ使う。
        let parent = directory.deletingLastPathComponent()
        if candidateURLs.isEmpty, parent != directory, let parentFiles = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) {
            candidateURLs.append(contentsOf: parentFiles.filter { $0.pathExtension.lowercased() == "inf" })
        }
        var map: [String: [String]] = [:]
        for infURL in candidateURLs {
            let infMap = parseINF(at: infURL)
            for (file, keys) in infMap where map[file] == nil {
                map[file] = keys
            }
        }
        return map
    }

    static func decodeINFText(_ data: Data) -> String {
        if data.count >= 2 && data[0] == 0xFF && data[1] == 0xFE {
            if let str = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
                return str
            }
        }
        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            if let str = String(data: data.dropFirst(3), encoding: .utf8) {
                return str
            }
        }
        if let str = String(data: data, encoding: .utf8) {
            return str
        }
        if let str = String(data: data, encoding: .utf16LittleEndian) {
            return str
        }
        if let str = String(data: data, encoding: .windowsCP1252) {
            return str
        }
        if let str = String(data: data, encoding: .shiftJIS) {
            return str
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func stripComment(_ line: String) -> String {
        var result = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
                result.append(ch)
            } else if ch == ";" && !inQuotes {
                break
            } else {
                result.append(ch)
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func splitCSVLine(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                tokens.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        tokens.append(current.trimmingCharacters(in: .whitespaces))
        return tokens
    }

    static func parseINF(at url: URL) -> [String: [String]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return parseINF(content: decodeINFText(data))
    }

    static func parseINF(content: String) -> [String: [String]] {
        var strings: [String: String] = [:]
        var inStrings = false
        var regLines: [String] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = stripComment(rawLine)
            if line.isEmpty { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let sectionName = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces).lowercased()
                inStrings = (sectionName == "strings")
                continue
            }
            if inStrings {
                let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    let key = parts[0].lowercased()
                    let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'\t "))
                    strings[key] = value
                }
            } else if line.localizedCaseInsensitiveContains("control panel\\cursors") {
                regLines.append(line)
            }
        }

        func resolveVariables(_ text: String) -> String {
            var resolved = text
            for _ in 0..<5 {
                var replaced = false
                for (key, val) in strings {
                    let pattern = "%\(key)%"
                    if resolved.localizedCaseInsensitiveContains(pattern) {
                        resolved = resolved.replacingOccurrences(of: pattern, with: val, options: .caseInsensitive)
                        replaced = true
                    }
                }
                if !replaced { break }
            }
            return resolved
        }

        let standardRoles: [[String]?] = [
            arrowTargets,        // 0: Normal
            helpTargets,         // 1: Help
            workingTargets,      // 2: Working
            nil,                 // 3: Busy
            precisionTargets,    // 4: Precision
            textTargets,         // 5: Text
            nil,                 // 6: Handwriting
            unavailableTargets,  // 7: Unavailable
            verticalTargets,     // 8: Vertical
            horizontalTargets,   // 9: Horizontal
            diagonal1Targets,    // 10: Diagonal 1
            diagonal2Targets,    // 11: Diagonal 2
            moveTargets,         // 12: Move
            nil,                 // 13: Alternate
            linkTargets,         // 14: Link
        ]

        let directRoleMap: [String: [String]] = [
            "arrow": arrowTargets,
            "help": helpTargets,
            "appstarting": workingTargets,
            "crosshair": precisionTargets,
            "precisionhair": precisionTargets,
            "ibeam": textTargets,
            "no": unavailableTargets,
            "sizens": verticalTargets,
            "sizewe": horizontalTargets,
            "sizenwse": diagonal1Targets,
            "sizenesw": diagonal2Targets,
            "sizeall": moveTargets,
            "hand": linkTargets,
        ]

        // 1 ファイルを複数の役割に使うテーマがあるので、上書きせず和集合にする。
        func merged(_ existing: [String]?, _ added: [String]) -> [String] {
            guard let existing else { return added }
            return existing + added.filter { !existing.contains($0) }
        }

        var result: [String: [String]] = [:]

        for line in regLines {
            let tokens = splitCSVLine(line)
            guard tokens.count >= 3 else { continue }
            let subkey = tokens[1].replacingOccurrences(of: "\\\\", with: "\\").lowercased()

            if subkey == "control panel\\cursors\\schemes" {
                let items: [String]
                if tokens.count == 5 && tokens[4].contains(",") {
                    items = tokens[4].split(separator: ",", omittingEmptySubsequences: false).map {
                        String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"'\t "))
                    }
                } else if tokens.count > 4 {
                    items = tokens[4...].map {
                        $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\t "))
                    }
                } else {
                    continue
                }

                for (idx, item) in items.enumerated() where idx < standardRoles.count {
                    guard let target = standardRoles[idx] else { continue }
                    guard !item.isEmpty else { continue }
                    let resolved = resolveVariables(item)
                    let fileName = URL(fileURLWithPath: resolved.replacingOccurrences(of: "\\", with: "/")).lastPathComponent.lowercased()
                    if (fileName.hasSuffix(".cur") || fileName.hasSuffix(".ani")) {
                        result[fileName] = merged(result[fileName], target)
                    }
                }
            } else if subkey == "control panel\\cursors" {
                let roleName = tokens[2].trimmingCharacters(in: CharacterSet(charactersIn: "\"'\t ")).lowercased()
                guard let target = directRoleMap[roleName] else { continue }
                guard tokens.count >= 5 else { continue }
                let item = tokens[4].trimmingCharacters(in: CharacterSet(charactersIn: "\"'\t "))
                guard !item.isEmpty else { continue }
                let resolved = resolveVariables(item)
                let fileName = URL(fileURLWithPath: resolved.replacingOccurrences(of: "\\", with: "/")).lastPathComponent.lowercased()
                if (fileName.hasSuffix(".cur") || fileName.hasSuffix(".ani")) {
                    result[fileName] = merged(result[fileName], target)
                }
            }
        }

        return result
    }

    // MARK: - 解析

    struct Frame {
        var image: CGImage
        var hotspot: CGPoint
    }

    static func cursorRep(from data: Data, isAnimated: Bool, pixelsPerPoint: Int) throws -> CursorRep {
        let frames: [Frame]
        var durations: [Int]  // 1/60 秒単位。フレームごと
        if isAnimated {
            (frames, durations) = try parseANI(data)
        } else {
            frames = [try parseCUR(data)]
            durations = [0]
        }
        guard let first = frames.first else { throw CursorKitError.invalidCursor("フレームが無い") }
        let width = first.image.width
        let height = first.image.height
        guard frames.allSatisfy({ $0.image.width == width && $0.image.height == height }) else {
            throw CursorKitError.invalidCursor("フレームごとに画像の大きさが違う")
        }
        guard width % pixelsPerPoint == 0, height % pixelsPerPoint == 0 else {
            throw CursorKitError.invalidCursor("画像 \(width)x\(height) が --scale \(pixelsPerPoint) で割り切れない")
        }

        // 登録形式は全フレーム同じ間隔なので、間隔が違うなら最小公約数で割ってフレームを繰り返す。
        var sequence = frames
        var duration = 0.0
        if frames.count > 1 {
            let unit = durations.reduce(0) { gcd($0, $1) }
            guard unit > 0 else { throw CursorKitError.invalidCursor("フレームの表示時間が 0") }
            sequence = zip(frames, durations).flatMap { Array(repeating: $0, count: $1 / unit) }
            duration = Double(unit) / 60
        }

        return CursorRep(
            size: CGSize(width: width / pixelsPerPoint, height: height / pixelsPerPoint),
            hotspot: CGPoint(x: first.hotspot.x / Double(pixelsPerPoint), y: first.hotspot.y / Double(pixelsPerPoint)),
            frameCount: sequence.count, frameDuration: duration, images: [try stack(sequence.map(\.image))])
    }

    /// RIFF 'ACON'。anih(ヘッダー)・rate(ステップごとの 1/60 秒)・seq(ステップ→フレーム番号)・LIST fram の icon。
    static func parseANI(_ data: Data) throws -> (frames: [Frame], durations: [Int]) {
        guard data.count >= 12, data[0..<4].elementsEqual("RIFF".utf8), data[8..<12].elementsEqual("ACON".utf8) else {
            throw CursorKitError.invalidCursor("ANI ではない(RIFF ACON でない)")
        }
        var header: (steps: Int, jiffies: Int)?
        var rate: [Int]?
        var seq: [Int]?
        var icons: [Data] = []

        func walk(_ start: Int, _ end: Int) throws {
            var pos = start
            while pos + 8 <= end {
                let id = String(decoding: data[pos..<pos + 4], as: UTF8.self)
                let size = Int(data.le32(pos + 4))
                let body = pos + 8
                guard body + size <= data.count else { throw CursorKitError.invalidCursor("チャンク \(id) がファイルの外に出る") }
                switch id {
                case "LIST" where size >= 4 && String(decoding: data[body..<body + 4], as: UTF8.self) == "fram":
                    try walk(body + 4, body + size)
                case "anih":
                    guard size >= 36 else { throw CursorKitError.invalidCursor("anih が短い") }
                    guard data.le32(body + 32) & 1 != 0 else {
                        throw CursorKitError.invalidCursor("フレームが生の画像データ形式(未対応。icon 形式のみ)")
                    }
                    header = (Int(data.le32(body + 8)), Int(data.le32(body + 28)))
                case "rate":
                    rate = (0..<size / 4).map { Int(data.le32(body + $0 * 4)) }
                case "seq ":
                    seq = (0..<size / 4).map { Int(data.le32(body + $0 * 4)) }
                case "icon":
                    icons.append(data.subdata(in: body..<body + size))
                default:
                    break
                }
                pos = body + size + (size & 1)
            }
        }
        try walk(12, data.count)

        guard let header else { throw CursorKitError.invalidCursor("anih が無い") }
        let decoded = try icons.map(parseCUR)
        let order = seq ?? Array(0..<header.steps)
        guard order.count == header.steps, order.allSatisfy({ decoded.indices.contains($0) }) else {
            throw CursorKitError.invalidCursor("ステップ数 \(header.steps) とフレーム数 \(decoded.count) が合わない")
        }
        let durations = (0..<header.steps).map { rate?[$0] ?? header.jiffies }
        guard durations.allSatisfy({ $0 > 0 }) else { throw CursorKitError.invalidCursor("表示時間が 0 のステップがある") }
        return (order.map { decoded[$0] }, durations)
    }

    /// ICONDIR(type 2 = cursor)。大きい方の画像を取り、hotspot はディレクトリエントリの planes / bitCount 欄から読む。
    static func parseCUR(_ data: Data) throws -> Frame {
        guard data.count >= 22, data.le16(0) == 0, data.le16(2) == 2 else {
            throw CursorKitError.invalidCursor("CUR ではない(ICONDIR の type が 2 でない)")
        }
        let count = Int(data.le16(4))
        guard count >= 1, 6 + count * 16 <= data.count else { throw CursorKitError.invalidCursor("CUR のエントリが壊れている") }
        // 幅 0 は 256 を表す。
        let best = (0..<count).max { entryWidth(data, $0) < entryWidth(data, $1) }!
        let entry = 6 + best * 16
        let hotspot = CGPoint(x: Int(data.le16(entry + 4)), y: Int(data.le16(entry + 6)))

        // ImageIO は .cur の単独ファイルを ICO として読めるので、選んだエントリだけの CUR に作り直して渡す。
        let size = Int(data.le32(entry + 8))
        let offset = Int(data.le32(entry + 12))
        guard offset + size <= data.count else { throw CursorKitError.invalidCursor("CUR の画像データがファイルの外に出る") }
        var single = Data(data[0..<6])
        single.replaceSubrange(4..<6, with: [1, 0])
        var dir = Data(data[entry..<entry + 16])
        dir.replaceSubrange(12..<16, with: UInt32(22).leBytes)
        single += dir
        single += data[offset..<offset + size]

        guard let source = CGImageSourceCreateWithData(single as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CursorKitError.invalidCursor("CUR の画像を ImageIO で読めない") }
        return Frame(image: normalizedImage(image), hotspot: hotspot)
    }

    private static func entryWidth(_ data: Data, _ index: Int) -> Int {
        let w = Int(data[6 + index * 16])
        return w == 0 ? 256 : w
    }

    /// 先頭フレームが上。
    static func stack(_ images: [CGImage]) throws -> CGImage {
        let w = images[0].width
        let h = images[0].height
        guard
            let ctx = CGContext(
                data: nil, width: w, height: h * images.count, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CursorKitError.io("フレームを並べる画像を作れない") }
        for (i, image) in images.enumerated() {
            ctx.draw(image, in: CGRect(x: 0, y: (images.count - 1 - i) * h, width: w, height: h))
        }
        return ctx.makeImage()!
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

extension Data {
    fileprivate func le16(_ offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    fileprivate func le32(_ offset: Int) -> UInt32 {
        UInt32(le16(offset)) | UInt32(le16(offset + 2)) << 16
    }
}

extension UInt32 {
    fileprivate var leBytes: [UInt8] { (0..<4).map { UInt8((self >> ($0 * 8)) & 0xff) } }
}
