import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import CursorKit

final class WindowsCursorImporterTests: XCTestCase {
    func testINFSharedFileMapsToAllRoles() {
        let inf = """
            [Scheme.Reg]
            HKCU,"Control Panel\\Cursors\\Schemes","T",,"a.cur,b.cur,b.cur,,,,,,,,,,,,"
            """
        let map = WindowsCursorImporter.parseINF(content: inf)
        XCTAssertEqual(map["b.cur"], ["Help", "BusyButClickable"])
    }

    func testLegacyRoleMapKeys() {
        XCTAssertEqual(WindowsCursorImporter.roleMap["normal"], ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["text"], ["ibeam"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["link"], ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["help"], ["Help"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["working"], ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["unavailable"], ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["precision"], ["Cross"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["move"], ["WindowMove"])
        XCTAssertEqual(
            WindowsCursorImporter.roleMap["horizontal"],
            [
                "ResizeLeftRight", "ResizeLeft", "ResizeRight", "WindowResizeEastWest", "WindowResizeEast",
                "WindowResizeWest",
            ])
        XCTAssertEqual(
            WindowsCursorImporter.roleMap["vertical"],
            [
                "ResizeUpDown", "ResizeUp", "ResizeDown", "WindowResizeNorthSouth", "WindowResizeNorth",
                "WindowResizeSouth",
            ])
        XCTAssertEqual(
            WindowsCursorImporter.roleMap["diagonal1"],
            ["WindowResizeNorthWestSouthEast", "WindowResizeNorthWest", "WindowResizeSouthEast"])
        XCTAssertEqual(
            WindowsCursorImporter.roleMap["diagonal2"],
            ["WindowResizeNorthEastSouthWest", "WindowResizeNorthEast", "WindowResizeSouthWest"])
    }

    func testExpandedRoleMapKeys() {
        XCTAssertEqual(WindowsCursorImporter.roleMap["arrow"], ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["pointer"], ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["default"], ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["ibeam"], ["ibeam"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["beam"], ["ibeam"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["hand"], ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["pointinghand"], ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["cross"], ["Cross"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["crosshair"], ["Cross"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["appstarting"], ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["notallowed"], ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["forbidden"], ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["sizeall"], ["WindowMove"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["sizewe"], WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["size_we"], WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["sizens"], WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["size_ns"], WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["sizenwse"], WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["size_nwse"], WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["dgn1"], WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["sizenesw"], WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["size_nesw"], WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleMap["dgn2"], WindowsCursorImporter.roleMap["diagonal2"])
    }

    func testRoleKeysDelimiterVariations() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "normal-select"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "normal_select"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Normal Select"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "NormalSelect"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "horizontal-resize"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "horizontal_resize"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Horizontal Resize"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "size-ns"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "size_we"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "diagonal_resize_1"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "diagonal-resize-2"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "link-select"), ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "working_in_background"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "not-allowed"), ["NotAllowed"])
    }

    func testRoleKeysNumberedPrefixes() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "01-Normal"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "01_normal"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "01 Normal"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "02-Link"), ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "03-Loading"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "04-Help"), ["Help"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "05-Text Select"), ["ibeam"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "07-Precision"), ["Cross"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "08-Unavailable"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "11-Vertical Resize"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "12-Horizontal Resize"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "13-Diagonal Resize 1"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "14-Diagonal Resize 2"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "15-Move"), ["WindowMove"])
    }

    func testRoleKeysThemePrefixesAndSuffixes() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Frieren normal"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Furina text"), ["ibeam"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Posy beam"), ["ibeam"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Posy forbidden"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "millennium_diag1"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "millennium_NS"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "normal-mini"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "loading-mini"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "working_1x"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "arrow-large"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "text_static"), ["ibeam"])
    }

    func testRoleKeysCombinedPrefixAndSuffix() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "01-Normal-large"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "01_normal_1x"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "03-loading-mini"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "12-Horizontal Resize-mini"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "13-Diagonal Resize 1-large"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "text_static_mini"), ["ibeam"])
    }

    func testRoleKeysDirectionalAndCSSNames() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "n-resize"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "s-resize"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "top_side"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "bottom_side"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "e-resize"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "w-resize"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "left_side"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "right_side"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "nw-resize"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "se-resize"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "top_left_corner"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "bottom_right_corner"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Resize_1"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "resize1"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "ne-resize"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "sw-resize"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "top_right_corner"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "bottom_left_corner"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "resize_2"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "resize2"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Posy cursor"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "hand1"), ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "dnd-move"), ["WindowMove"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "dnd-none"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "dnd-no-drop"), ["NotAllowed"])
    }

    func testRoleKeysTypoTolerances() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "dng1"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "dng2"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "unavailiable"), ["NotAllowed"])
    }

    func testRoleKeysJapaneseNames() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "通常の選択"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "通常"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "テキスト選択"), ["ibeam"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "リンク選択"), ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "ヘルプ"), ["Help"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "バックグラウンド作業中"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "利用不可"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "精密選択"), ["Cross"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "上下に拡大・縮小"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "左右に拡大・縮小"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "斜めに拡大・縮小1"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "斜めに拡大・縮小2"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "移動"), ["WindowMove"])
    }

    func testRoleKeysExtendedMacOS() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "copy"), ["Copy"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "alias"), ["MakeAlias"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "context-menu"), ["ContextualMenu"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "vertical-text"), ["IBeamVertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "openhand"), ["OpenHand"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "closedhand"), ["ClosedHand"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "zoom-in"), ["ZoomIn"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "zoom-out"), ["ZoomOut"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "cell"), ["Cell"])
    }

    func testINFParser() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let infContent = """
        [Version]
        signature="$CHICAGO$"

        [Scheme.Reg]
        HKCU,"Control Panel\\Cursors\\Schemes","%SCHEME_NAME%",,"%10%\\%CUR_DIR%\\%pointer%,%10%\\%CUR_DIR%\\%help%,%10%\\%CUR_DIR%\\%work%,%10%\\%CUR_DIR%\\%busy%,%10%\\%CUR_DIR%\\%cross%,%10%\\%CUR_DIR%\\%text%,%10%\\%CUR_DIR%\\%hand%,%10%\\%CUR_DIR%\\%unavail%,%10%\\%CUR_DIR%\\%vert%,%10%\\%CUR_DIR%\\%horz%,%10%\\%CUR_DIR%\\%dgn1%,%10%\\%CUR_DIR%\\%dgn2%,%10%\\%CUR_DIR%\\%move%,%10%\\%CUR_DIR%\\%alt%,%10%\\%CUR_DIR%\\%link%"

        [Strings]
        CUR_DIR = "Cursors\\CustomTheme"
        SCHEME_NAME = "Custom Theme"
        pointer = "my_custom_normal.cur"
        help = "my_custom_help.cur"
        work = "my_custom_work.ani"
        busy = "my_custom_busy.ani"
        cross = "my_custom_cross.cur"
        text = "my_custom_text.cur"
        hand = "my_custom_pen.cur"
        unavail = "my_custom_block.cur"
        vert = "my_custom_v.cur"
        horz = "my_custom_h.cur"
        dgn1 = "my_custom_d1.cur"
        dgn2 = "my_custom_d2.cur"
        move = "my_custom_m.cur"
        alt = "my_custom_up.cur"
        link = "my_custom_hand.cur"
        """

        let infURL = tempDir.appendingPathComponent("install.inf")
        try infContent.write(to: infURL, atomically: true, encoding: .utf8)

        let infMap = WindowsCursorImporter.loadINFRoleMap(for: tempDir)
        XCTAssertEqual(infMap["my_custom_normal.cur"], ["arrow"])
        XCTAssertEqual(infMap["my_custom_help.cur"], ["Help"])
        XCTAssertEqual(infMap["my_custom_work.ani"], ["BusyButClickable"])
        XCTAssertEqual(infMap["my_custom_cross.cur"], ["Cross"])
        XCTAssertEqual(infMap["my_custom_text.cur"], ["ibeam"])
        XCTAssertEqual(infMap["my_custom_block.cur"], ["NotAllowed"])
        XCTAssertEqual(infMap["my_custom_v.cur"], WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(infMap["my_custom_h.cur"], WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(infMap["my_custom_d1.cur"], WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(infMap["my_custom_d2.cur"], WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(infMap["my_custom_m.cur"], ["WindowMove"])
        XCTAssertEqual(infMap["my_custom_hand.cur"], ["pointingHand"])
    }

    func testINFParserWithMissingSlots() {
        // Slot 3 (Busy), Slot 6 (Handwriting), Slot 13 (Alternate) are empty.
        // Positions must NOT shift subsequent roles!
        let infContent = """
        [Scheme.Reg]
        HKCU,"Control Panel\\Cursors\\Schemes","PartialScheme",,"%10%\\arrow.cur,%10%\\help.cur,%10%\\work.ani,,%10%\\cross.cur,%10%\\text.cur,,%10%\\unavail.cur,%10%\\vert.cur,%10%\\horz.cur,%10%\\dgn1.cur,%10%\\dgn2.cur,%10%\\move.cur,,%10%\\link.cur"
        """
        let map = WindowsCursorImporter.parseINF(content: infContent)
        XCTAssertEqual(map["arrow.cur"], ["arrow"])
        XCTAssertEqual(map["help.cur"], ["Help"])
        XCTAssertEqual(map["work.ani"], ["BusyButClickable"])
        XCTAssertEqual(map["cross.cur"], ["Cross"])
        XCTAssertEqual(map["text.cur"], ["ibeam"])
        XCTAssertEqual(map["unavail.cur"], ["NotAllowed"])
        XCTAssertEqual(map["vert.cur"], WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(map["horz.cur"], WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(map["dgn1.cur"], WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(map["dgn2.cur"], WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(map["move.cur"], ["WindowMove"])
        XCTAssertEqual(map["link.cur"], ["pointingHand"])
    }

    func testINFParserDirectEntries() {
        let infContent = """
        [Scheme.Reg]
        HKCU,"Control Panel\\Cursors",Arrow,0x00020000,"%10%\\%CUR_DIR%\\my_arrow.cur"
        HKCU,"Control Panel\\Cursors",IBeam,0x00020000,"%10%\\%CUR_DIR%\\my_ibeam.cur"
        HKCU,"Control Panel\\Cursors",Hand,0x00020000,"%10%\\%CUR_DIR%\\my_link.cur"
        HKCU,"Control Panel\\Cursors",SizeWE,0x00020000,"%10%\\%CUR_DIR%\\my_we.cur"

        [Strings]
        CUR_DIR = "Cursors\\Theme"
        """
        let map = WindowsCursorImporter.parseINF(content: infContent)
        XCTAssertEqual(map["my_arrow.cur"], ["arrow"])
        XCTAssertEqual(map["my_ibeam.cur"], ["ibeam"])
        XCTAssertEqual(map["my_link.cur"], ["pointingHand"])
        XCTAssertEqual(map["my_we.cur"], WindowsCursorImporter.roleMap["horizontal"])
    }

    func testINFParserUTF16LE() {
        let infContent = """
        [Scheme.Reg]
        HKCU,"Control Panel\\Cursors\\Schemes","UTF16Scheme",,"%10%\\utf16_arrow.cur,%10%\\utf16_help.cur"
        """
        var data = Data([0xFF, 0xFE]) // UTF-16 LE BOM
        data.append(infContent.data(using: .utf16LittleEndian)!)

        let text = WindowsCursorImporter.decodeINFText(data)
        let map = WindowsCursorImporter.parseINF(content: text)
        XCTAssertEqual(map["utf16_arrow.cur"], ["arrow"])
        XCTAssertEqual(map["utf16_help.cur"], ["Help"])
    }

    func testRoleKeysFullwidthAndDelimiterVariations() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "チルノ　マウスカーソル　通常"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "東方　マウスカーソル　左右に拡大・縮小"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "01　通常"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "cursor~normal"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "pointer+arrow"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "test\tlink"), ["pointingHand"])
    }

    func testRoleKeysParenthesizedMetadata() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Pointer (Red)"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Help (Mirrored)"), ["Help"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "STMC 45-Degree 01 Pointer (Red)"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "STMC 45-Degree 03 Pointer with Spinner (White)"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "Link (1)"), ["pointingHand"])
    }

    func testRoleKeysAeroAndShort83Names() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_arrow"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_arrow_l"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_arrow_xl"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero-working"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_working_r"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_helpsel"), ["Help"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_cross"), ["Cross"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_move"), ["WindowMove"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_unavail"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_ew"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_ns"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_nwse"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_nesw"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_link"), ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "aero_beam"), ["ibeam"])

        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "larrow"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "marrow"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "sarrow"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "libeam"), ["ibeam"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "lcross"), ["Cross"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "lappstrt"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "lmove"), ["WindowMove"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "lns"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "lwe"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "lnwse"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "lnesw"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "lnodrop"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "lhelp"), ["Help"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "lhand"), ["pointingHand"])
    }

    func testRoleKeysWindowsClassicSizes() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "size1"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "size1_r"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "size2"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "size2_r"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "size3"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "size3_r"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "size4"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "size4_r"), WindowsCursorImporter.roleMap["horizontal"])
    }

    func testRoleKeysPlusAndRetroThemes() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dgarro"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dwarro"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dgmove"), ["WindowMove"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dsmove"), ["WindowMove"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dwmove"), ["WindowMove"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "hmove"), ["WindowMove"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dgno"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dwno"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "handno"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dgns"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dsns"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dwns"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "hns"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "handns"), WindowsCursorImporter.roleMap["vertical"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dgwe"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "3dwwe"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "hwe"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "handwe"), WindowsCursorImporter.roleMap["horizontal"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "handapst"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "appstar"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "apst"), ["BusyButClickable"])
    }

    func testRoleKeysAdditionalAliases() {
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "main-cursor"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "standard_cursor"), ["arrow"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "arro"), ["arrow"])

        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "リンクの選択"), ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "pointing-finger"), ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "hand-point"), ["pointingHand"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "weblink"), ["pointingHand"])

        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "pointer with spinner"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "arrow with spinner"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "working-in-bg"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "arrow-wait"), ["BusyButClickable"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "counter"), ["BusyButClickable"])

        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "prohibited"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "banned"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "no-entry"), ["NotAllowed"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "cant-drop"), ["NotAllowed"])

        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "precisionhair"), ["Cross"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "cross_hair"), ["Cross"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "sight"), ["Cross"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "bullseye"), ["Cross"])

        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "four-way"), ["WindowMove"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "4way"), ["WindowMove"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "arrows-all"), ["WindowMove"])

        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "resize_di_1"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "stretch_tl_br"), WindowsCursorImporter.roleMap["diagonal1"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "diagonal-resize-backslash"), WindowsCursorImporter.roleMap["diagonal1"])

        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "resize_di_2"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "stretch_bl_tr"), WindowsCursorImporter.roleMap["diagonal2"])
        XCTAssertEqual(WindowsCursorImporter.roleKeys(for: "diagonal-resize-frontslash"), WindowsCursorImporter.roleMap["diagonal2"])
    }

    func testINFParserPrecisionhair() {
        let infContent = """
        [Scheme.Reg]
        HKCU,"Control Panel\\Cursors",Precisionhair,0x00020000,"%10%\\my_precision.cur"
        """
        let map = WindowsCursorImporter.parseINF(content: infContent)
        XCTAssertEqual(map["my_precision.cur"], ["Cross"])
    }

    func testImportThemeWithMockFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let curData = makeMockCUR(width: 16, height: 16)
        try curData.write(to: tempDir.appendingPathComponent("01-normal.cur"))
        try curData.write(to: tempDir.appendingPathComponent("text-select.cur"))
        try curData.write(to: tempDir.appendingPathComponent("size_we.cur"))
        try curData.write(to: tempDir.appendingPathComponent("unsupported_xyz.cur"))
        try "readme".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("readme.txt"))

        let result = try WindowsCursorImporter.importTheme(directory: tempDir, name: "TestTheme", pixelsPerPoint: 1)
        XCTAssertEqual(result.theme.name, "TestTheme")
        XCTAssertNotNil(result.theme.cursors["arrow"])
        XCTAssertNotNil(result.theme.cursors["ibeam"])
        XCTAssertNotNil(result.theme.cursors["ResizeLeftRight"])
        XCTAssertTrue(result.skippedFiles.contains("unsupported_xyz.cur"))
        XCTAssertFalse(result.skippedFiles.contains("readme.txt"))
    }

    func testAnimatedImportReducesFramesAndPreservesExplicitRates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try! FileManager.default.removeItem(at: directory) }
        func integer(_ value: UInt32) -> Data {
            withUnsafeBytes(of: value.littleEndian) { Data($0) }
        }
        func chunk(_ name: String, _ contents: Data) -> Data {
            Data(name.utf8) + integer(UInt32(contents.count)) + contents
                + (contents.count % 2 == 1 ? Data([0]) : Data())
        }
        let header: [UInt32] = [36, 54, 54, 0, 0, 0, 0, 1, 1]
        let icons = (0..<54).reduce(Data("fram".utf8)) { data, _ in
            data + chunk("icon", makeMockCUR(width: 16, height: 16))
        }
        let acon =
            Data("ACON".utf8)
            + chunk("anih", header.reduce(Data()) { $0 + integer($1) })
            + chunk("rate", (0..<54).reduce(Data()) { data, _ in data + integer(2) })
            + chunk("LIST", icons)
        try (Data("RIFF".utf8) + integer(UInt32(acon.count)) + acon)
            .write(to: directory.appendingPathComponent("Work.ani"))
        let imported = try CursorTheme.importSource(directory, name: nil, pixelsPerPoint: 1)
        XCTAssertEqual(imported.adjustments.count, 1)
        XCTAssertTrue(imported.skipped.isEmpty)
        let rep = imported.theme.cursors["BusyButClickable"]!
        XCTAssertEqual(rep.frameCount, 24)
        XCTAssertEqual(rep.frameDuration * 24, 1.8, accuracy: 0.000001)
        XCTAssertEqual(rep.images[0].height, 16 * 24)
        _ = try imported.theme.resolvedPlan()
    }

    func testAnimationWithFewerRateEntriesThanStepsIsRejected() throws {
        func integer(_ value: UInt32) -> Data {
            withUnsafeBytes(of: value.littleEndian) { Data($0) }
        }
        func chunk(_ name: String, _ contents: Data) -> Data {
            Data(name.utf8) + integer(UInt32(contents.count)) + contents
                + (contents.count % 2 == 1 ? Data([0]) : Data())
        }
        let header: [UInt32] = [36, 2, 2, 0, 0, 0, 0, 1, 1]
        let icons = (0..<2).reduce(Data("fram".utf8)) { data, _ in
            data + chunk("icon", makeMockCUR(width: 16, height: 16))
        }
        let acon =
            Data("ACON".utf8) + chunk("anih", header.reduce(Data()) { $0 + integer($1) })
            + chunk("rate", integer(5)) + chunk("LIST", icons)
        XCTAssertThrowsError(try WindowsCursorImporter.parseANI(Data("RIFF".utf8) + integer(UInt32(acon.count)) + acon))
    }

    func testCapeWithOutOfRangeNumbersIsRejectedInsteadOfCrashing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try! FileManager.default.removeItem(at: directory) }
        let png = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        for (key, value) in [("FrameCount", 1e30), ("PointsWide", Double.infinity), ("PointsHigh", Double.nan)] {
            var cursor: [String: Any] = [
                "PointsWide": 1.0, "PointsHigh": 1.0, "FrameCount": 1.0, "FrameDuration": 1.0, "HotSpotX": 0.0,
                "HotSpotY": 0.0, "Representations": [png],
            ]
            cursor[key] = value
            let file = directory.appendingPathComponent("\(key).cape")
            try PropertyListSerialization.data(
                fromPropertyList: ["Cursors": ["com.apple.coregraphics.ArrowS": cursor]], format: .binary, options: 0
            ).write(to: file)
            XCTAssertThrowsError(try CapeImporter.importTheme(file: file, name: nil), key)
        }
    }

    func testFileSharingARoleWithAnEarlierFileStillFillsFreeRoles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try! FileManager.default.removeItem(at: directory) }
        try makeMockCUR(width: 16, height: 16).write(to: directory.appendingPathComponent("size_left.cur"))
        try makeMockCUR(width: 16, height: 16).write(to: directory.appendingPathComponent("horizontal.cur"))
        let result = try WindowsCursorImporter.importTheme(directory: directory, name: "t", pixelsPerPoint: 1)
        XCTAssertNotNil(result.theme.cursors["WindowResizeEastWest"])
        XCTAssertNotNil(result.theme.cursors["ResizeLeft"])
        XCTAssertNotNil(result.theme.cursors["ResizeLeftRight"])
    }

    // MARK: - Helpers

    private func makeMockCUR(width: Int, height: Int) -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let pngData = NSMutableData()
        let dest = CGImageDestinationCreateWithData(pngData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)

        var cur = Data()
        cur.append(contentsOf: [0, 0])
        cur.append(contentsOf: [2, 0])
        cur.append(contentsOf: [1, 0])
        cur.append(UInt8(width))
        cur.append(UInt8(height))
        cur.append(0)
        cur.append(0)
        cur.append(contentsOf: [0, 0])
        cur.append(contentsOf: [0, 0])
        let pngLen = UInt32(pngData.length)
        cur.append(contentsOf: [
            UInt8(pngLen & 0xff), UInt8((pngLen >> 8) & 0xff), UInt8((pngLen >> 16) & 0xff), UInt8((pngLen >> 24) & 0xff),
        ])
        let offset = UInt32(22)
        cur.append(contentsOf: [
            UInt8(offset & 0xff), UInt8((offset >> 8) & 0xff), UInt8((offset >> 16) & 0xff),
            UInt8((offset >> 24) & 0xff),
        ])
        cur.append(pngData as Data)
        return cur
    }
}
