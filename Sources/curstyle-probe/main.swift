import CCursorBridge
import CoreGraphics
import Foundation

let usage = """
    usage: curstyle-probe <command>
      symbols            非公開シンボルの解決結果
      names              CGSCursorNameForSystemCursor の表と、OS 内の識別子名候補
      dump               標準カーソルと登録済みカーソルの画像情報・別名グループ(読み取りのみ)
      swap <n1,n2,..> [sec]  各名前をテスト画像に差し替え、sec 秒後に元へ戻して読み戻す
      apply <name>...    テスト画像を登録したまま終了する
      register-core <id> <name>...  CoreCursorCopyImages(id) の画像を name に登録する
      remove <name>...   登録を削除して読み戻す
      read <name>...     登録内容を読むだけ(別プロセスからの見え方を確かめる用)
      restore            CoreCursorUnregisterAll で標準へ戻す(緊急用)
    """

let args = CommandLine.arguments.dropFirst()
guard let command = args.first else {
    print(usage)
    exit(2)
}

let cursors = try Cursors()

@MainActor func symbols() {
    let names = [
        "CGSMainConnectionID", "CGSCursorNameForSystemCursor", "CGSRegisterCursorWithImages",
        "CGSCopyRegisteredCursorImages", "CGSRemoveRegisteredCursor", "CoreCursorUnregisterAll",
        "CoreCursorCopyImages", "CoreCursorSet", "CGSGetCursorScale", "CGSSetCursorScale",
        "CGSSetSystemDefinedCursor", "CGSSetDockCursorOverride",
    ]
    for n in names {
        let path = CSImagePathForSymbol(n).map { String(cString: $0) } ?? "MISSING"
        print("\(n)\t\(path)")
    }
    print("connection=\(cursors.cid)")
    if let (err, scale) = try? cursors.cursorScale() { print("cursorScale err=\(err) scale=\(scale)") }
}

@MainActor func candidateNames() -> [String] {
    var set = Set<String>()
    for prefix in ["com.apple.coregraphics.", "com.apple.cursor."] {
        for sym in ["CGSRegisterCursorWithImages", "CoreCursorCopyImages"] {
            set.formUnion(cursors.scanNames(prefix: prefix, inImageOf: sym))
        }
    }
    return set.sorted()
}

@MainActor func names() {
    print("# CGSCursorNameForSystemCursor(id) for id in -64..<4096")
    if let fn = cursors.sym.cursorNameForSystemCursor {
        for id in Int32(-64)..<4096 {
            if let p = fn(id) { print("\(id)\t\(String(cString: p))") }
        }
    }
    print("# __cstring の識別子名候補 (SkyLight / HIServices)")
    for n in candidateNames() { print(n) }
}

@MainActor func dump() throws {
    var groups: [String: [String]] = [:]
    print("# CoreCursorCopyImages(id)")
    for id in Int32(0)..<128 {
        let (err, data) = try cursors.copyCore(id)
        guard let data else {
            print("core \(id)\terr=\(err)")
            continue
        }
        print("core \(id)\t\(data.summary)")
        groups[data.pixelHash, default: []].append("core:\(id)")
    }
    print("# CGSCopyRegisteredCursorImages(name)")
    var tried = candidateNames().filter { !$0.contains("%") }
    tried += (0..<128).map { "com.apple.cursor.\($0)" }
    for name in Array(Set(tried)).sorted() {
        let (err, data) = try cursors.copyRegistered(name)
        guard let data else {
            print("reg \(name)\terr=\(err)")
            continue
        }
        print("reg \(name)\t\(data.summary)")
        groups[data.pixelHash, default: []].append(name)
    }
    print("# 別名グループ (同一ピクセル)")
    for (hash, members) in groups.sorted(by: { $0.key < $1.key }) where members.count > 1 {
        print("\(hash)\t\(members.joined(separator: " "))")
    }
}

// 赤い枠つきの三角形。標準の矢印と一目で区別できることだけが目的。
func testImage(pointSize: Int, scale: Int) -> CGImage {
    let px = pointSize * scale
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    let p = CGFloat(pointSize)
    // CGContext は左下原点。hotspot (0,0) = 左上に先端を置く。
    ctx.move(to: CGPoint(x: 1, y: p - 1))
    ctx.addLine(to: CGPoint(x: p * 0.75, y: p * 0.45))
    ctx.addLine(to: CGPoint(x: 1, y: p * 0.2))
    ctx.closePath()
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0.1, blue: 0.1, alpha: 1))
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(1.5)
    ctx.drawPath(using: .fillStroke)
    return ctx.makeImage()!
}

// 1つの登録が別名や CoreCursor 側の画像にどう波及するかを見る。
@MainActor func printRelated(_ label: String) throws {
    var names = ["com.apple.coregraphics.ConnectionCurrent", "com.apple.coregraphics.GlobalCurrent"]
    if let fn = cursors.sym.cursorNameForSystemCursor {
        names += (Int32(0)..<128).compactMap { fn($0).map { String(cString: $0) } }
    }
    for n in names {
        let (e, d) = try cursors.copyRegistered(n)
        print("  \(label) \(n)\terr=\(e) hash=\(d?.pixelHash ?? "-")")
    }
    for id: Int32 in [0, 1] {
        let (e, d) = try cursors.copyCore(id)
        print("  \(label) core:\(id)\terr=\(e) hash=\(d?.pixelHash ?? "-")")
    }
}

// names はカンマ区切り。全部を登録してから待ち、全部を元に戻す。
@MainActor func swap(names: [String], seconds: Double) throws {
    let test = CursorData(
        size: CGSize(width: 32, height: 32), hotspot: .zero, frameCount: 1, frameDuration: 0,
        images: [testImage(pointSize: 32, scale: 2)])
    print("test=\(test.pixelHash)")
    var befores: [String: CursorData] = [:]
    for name in names {
        let (beforeErr, before) = try cursors.copyRegistered(name)
        befores[name] = before
        print("before \(name)\terr=\(beforeErr)\t\(before?.summary ?? "-")")
        let (regErr, seed) = try cursors.register(name, test)
        print("register \(name)\terr=\(regErr) seed=\(seed)")
        let (afterErr, after) = try cursors.copyRegistered(name)
        print("readback \(name)\terr=\(afterErr)\thash=\(after?.pixelHash ?? "-")")
    }
    try printRelated("applied")
    print("waiting \(seconds)s — 画面のカーソルを確認してください")
    Thread.sleep(forTimeInterval: seconds)

    for name in names {
        if let before = befores[name] {
            let (e, s) = try cursors.register(name, before)
            print("restore(re-register) \(name)\terr=\(e) seed=\(s)")
        } else {
            print("restore(remove) \(name)\terr=\(try cursors.remove(name))")
        }
        let (finalErr, final) = try cursors.copyRegistered(name)
        print(
            "final \(name)\terr=\(finalErr)\thash=\(final?.pixelHash ?? "-") matchesBefore=\(final?.pixelHash == befores[name]?.pixelHash)"
        )
    }
    try printRelated("restored")
}

switch command {
case "symbols": symbols()
case "names": names()
case "dump": try dump()
case "swap":
    let a = Array(args.dropFirst())
    guard let name = a.first else {
        print(usage)
        exit(2)
    }
    try swap(names: name.split(separator: ",").map(String.init), seconds: a.count > 1 ? Double(a[1])! : 5)
case "apply":
    // 元に戻さずに終了する。プロセス終了後に登録が残るか、復元経路が何を戻すかを測る用。
    let test = CursorData(
        size: CGSize(width: 32, height: 32), hotspot: .zero, frameCount: 1, frameDuration: 0,
        images: [testImage(pointSize: 32, scale: 2)])
    for name in args.dropFirst() {
        let (e, seed) = try cursors.register(name, test)
        print("apply \(name)\terr=\(e) seed=\(seed) test=\(test.pixelHash)")
    }
case "register-core":
    // CoreCursorCopyImages(id) の標準画像を name に登録し直す。ArrowS/IBeamS の復元用。
    let a = Array(args.dropFirst())
    let (ce, core) = try cursors.copyCore(Int32(a[0])!)
    guard let core else { throw ProbeError(description: "CoreCursorCopyImages(\(a[0])) err=\(ce)") }
    for name in a.dropFirst() {
        let (e, _) = try cursors.register(name, core)
        let (re, rd) = try cursors.copyRegistered(name)
        print("register-core \(a[0]) -> \(name)\terr=\(e) readback err=\(re) match=\(rd?.pixelHash == core.pixelHash)")
    }
case "remove":
    for name in args.dropFirst() {
        let e = try cursors.remove(name)
        let (re, rd) = try cursors.copyRegistered(name)
        print("remove \(name)\terr=\(e) readback err=\(re)\t\(rd?.summary ?? "-")")
    }
case "read":
    for name in args.dropFirst() {
        let (e, d) = try cursors.copyRegistered(name)
        print("read \(name)\terr=\(e)\t\(d?.summary ?? "-")")
    }
case "restore": print("CoreCursorUnregisterAll err=\(try cursors.unregisterAll())")
default:
    print(usage)
    exit(2)
}
