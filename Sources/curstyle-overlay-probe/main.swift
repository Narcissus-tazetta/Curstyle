import AppKit
import CryptoKit

// OverlayBackend の実現性測定用(配布しない)。結果は docs/PHASE3_5.md。

let usage = """
    usage: curstyle-overlay-probe <command>
      hide [--prop] [--cgs] [--rehide] [sec]  CGDisplayHideCursor で隠して sec 秒維持する。--prop で SetsCursorInBackground を立て、--cgs で CGSHideCursor を使い、--rehide でアプリ切替のたびに隠し直す
      overlay [--mode layer|window] [--source event|link|tap] [--keep-real] [--no-tint] [--exclude-capture] [--predict ms] [--pad] [sec]
                            本物を隠して自前カーソル(既定は赤く染めた現在の形)を描く
      table                 NSCursor のファクトリ(非公開含む)の照合用ハッシュ一覧
      watch [sec]           現在のシステムカーソルの seed と画像ハッシュを 0.2 秒ごとに記録する
    """

typealias SetPropFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
typealias ConnFn = @convention(c) () -> Int32
typealias SeedFn = @convention(c) () -> Int32

nonisolated(unsafe) let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
func sym<T>(_ name: String, _: T.Type) -> T? {
    guard let p = dlsym(skylight, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}
nonisolated(unsafe) let mainConnection = sym("CGSMainConnectionID", ConnFn.self)!
nonisolated(unsafe) let cgsHide = sym("CGSHideCursor", (@convention(c) (Int32) -> Int32).self)!
nonisolated(unsafe) let cgsShow = sym("CGSShowCursor", (@convention(c) (Int32) -> Int32).self)!
nonisolated(unsafe) let cursorSeed = sym("CGSCurrentCursorSeed", SeedFn.self)!
// CGCursorIsVisible は Swift から unavailable 扱いだが、シンボルは残っている。
nonisolated(unsafe) let cursorIsVisible = unsafeBitCast(
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible")!, to: (@convention(c) () -> UInt32).self)

func log(_ s: String) {
    let t = ISO8601DateFormatter.string(
        from: Date(), timeZone: .current, formatOptions: [.withTime, .withFractionalSeconds])
    print("\(t) \(s)")
    fflush(stdout)
}

/// 形の照合用ハッシュ。大きさ・hotspot と、最大解像度の画像を sRGB RGBA8 に描き直した画素で取る。
func shapeKey(size: CGSize, hotspot: CGPoint, image: CGImage?) -> String {
    guard let cg = image else { return "noimage" }
    let w = cg.width, h = cg.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(
        data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var hasher = SHA256()
    hasher.update(
        data: Data("\(Int(size.width))x\(Int(size.height));\(Int(hotspot.x)),\(Int(hotspot.y));\(w)x\(h)".utf8))
    hasher.update(data: Data(buf))
    return hasher.finalize().prefix(6).map { String(format: "%02x", $0) }.joined()
}

func largestImage(_ image: NSImage) -> CGImage? {
    let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
    if let best = reps.max(by: { $0.pixelsWide < $1.pixelsWide }) { return best.cgImage }
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

func cursorKey(_ c: NSCursor) -> String {
    shapeKey(size: c.image.size, hotspot: c.hotSpot, image: largestImage(c.image))
}

/// スナップショット(CGSBackend が保存した標準画像)から照合表を作る。アニメは1枚目のフレームを含む縦長画像のまま。
func snapshotShapes() -> [(String, String)] {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support/Curstyle/snapshot")
    guard let data = try? Data(contentsOf: dir.appending(path: "manifest.json")),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let entries = json["entries"] as? [String: [String: Any]]
    else { return [] }
    var out: [(String, String)] = []
    for (name, e) in entries {
        guard let r = e["registered"] as? [String: Any], let files = r["imageFiles"] as? [String] else { continue }
        let images = files.compactMap { f -> CGImage? in
            guard let src = CGImageSourceCreateWithURL(dir.appending(path: f) as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(src, 0, nil)
        }
        let best = images.max { $0.width < $1.width }
        let size = CGSize(width: r["width"] as! Double, height: r["height"] as! Double)
        let hot = CGPoint(x: r["hotspotX"] as! Double, y: r["hotspotY"] as! Double)
        out.append(
            (name.replacingOccurrences(of: "com.apple.", with: ""), shapeKey(size: size, hotspot: hot, image: best)))
    }
    return out.sorted { $0.0 < $1.0 }
}

// 呼ぶと例外で落ちるもの(macOS 27.2 で実測)
let brokenFactories: Set<String> = ["_moveCursor"]

func factoryCursors() -> [(String, NSCursor)] {
    var count: UInt32 = 0
    guard let meta = object_getClass(NSCursor.self), let methods = class_copyMethodList(meta, &count) else { return [] }
    defer { free(methods) }
    var out: [(String, NSCursor)] = []
    for i in 0..<Int(count) {
        let sel = method_getName(methods[i])
        let name = NSStringFromSelector(sel)
        guard !name.contains(":"), name.lowercased().hasSuffix("cursor"), name != "currentCursor",
            name != "currentSystemCursor", !brokenFactories.contains(name)
        else { continue }
        guard let r = (NSCursor.self as AnyObject).perform(sel)?.takeUnretainedValue() as? NSCursor else { continue }
        out.append((name, r))
    }
    // arrow / IBeam 系はメタクラスのメソッド一覧に出てこない(macOS 27.2 で実測)ので明示する
    out += [
        ("arrowCursor", .arrow), ("IBeamCursor", .iBeam),
        ("IBeamCursorForVerticalLayout", .iBeamCursorForVerticalLayout),
    ]
    return out.sorted { $0.0 < $1.0 }
}

nonisolated(unsafe) var shapeTable: [String: [String]] = [:]
func buildShapeTable() {
    for (name, c) in factoryCursors() { shapeTable[cursorKey(c), default: []].append(name) }
    for (name, key) in snapshotShapes() { shapeTable[key, default: []].append(name) }
}

func currentCursorDescription() -> String {
    guard let c = NSCursor.currentSystem else { return "currentSystem=nil" }
    let key = cursorKey(c)
    let shape = shapeTable[key]?.joined(separator: "|") ?? "UNKNOWN"
    return
        "shape=\(shape) key=\(key) size=\(Int(c.image.size.width))x\(Int(c.image.size.height)) hot=\(Int(c.hotSpot.x)),\(Int(c.hotSpot.y))"
}

func status() -> String {
    "visible=\(cursorIsVisible() != 0) seed=\(cursorSeed()) \(currentCursorDescription())"
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(2)
}
args.removeFirst()

switch command {
case "hide":
    buildShapeTable()
    let useProp = args.contains("--prop")
    let seconds = args.compactMap { Double($0) }.first ?? 10
    let cid = mainConnection()
    log("pid=\(getpid()) cid=\(cid) \(status())")
    if useProp {
        let setProp = sym("CGSSetConnectionProperty", SetPropFn.self)!
        let err = setProp(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        log("SetsCursorInBackground err=\(err)")
    }
    let useCGS = args.contains("--cgs")
    func hideOnce() -> Int32 { useCGS ? cgsHide(cid) : CGDisplayHideCursor(CGMainDisplayID()).rawValue }
    let err = hideOnce()
    log("\(useCGS ? "CGSHideCursor" : "CGDisplayHideCursor") err=\(err) \(status())")
    var hideCount = 1
    if args.contains("--rehide") {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app =
                (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "?"
            MainActor.assumeIsolated {
                log("activated \(app) before: \(status())")
                let e = hideOnce()
                hideCount += 1
                log("rehide err=\(e) count=\(hideCount) after: \(status())")
                // 切替先のアプリが通知より後で表示し直すことがあるので、1秒間だけ見張る
                let start = Date()
                Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { t in
                    MainActor.assumeIsolated {
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        if cursorIsVisible() != 0 {
                            _ = hideOnce()
                            hideCount += 1
                            log("  +\(ms)ms visible -> rehide count=\(hideCount) now visible=\(cursorIsVisible() != 0)")
                        }
                        if ms > 1000 { t.invalidate() }
                    }
                }
            }
        }
    }
    let end = Date().addingTimeInterval(seconds)
    var last = ""
    while Date() < end {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let s = status()
        if s != last { log(s); last = s }
    }
    let showErr = useCGS ? cgsShow(cid) : CGDisplayShowCursor(CGMainDisplayID()).rawValue
    log("show err=\(showErr) \(status())")
case "overlay":
    var o = OverlayOptions()
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "--mode": o.mode = it.next()!
        case "--source": o.source = it.next()!
        case "--keep-real": o.hideReal = false
        case "--no-tint": o.tint = false
        case "--predict": o.predictMs = Double(it.next()!)!
        case "--pad": o.pad = true
        case "--exclude-capture": o.excludeFromCapture = true
        default: o.seconds = Double(a)!
        }
    }
    OverlayProbe(options: o).run()
case "analyze":
    // マウス周囲を -C あり/なしで撮った2枚から、本物が描かれているか(2枚の差)と、
    // 自前カーソル(赤く染めた画素)が写っているかを出す
    func load(_ path: String) -> (CGImage, [UInt8]) {
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = CGContext(
            data: &buf, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return (img, buf)
    }
    let (_, withCursor) = load(args[0])
    let (_, without) = load(args[1])
    var diff = 0
    var red = 0
    var colors: [String: Int] = ["magenta": 0, "cyan": 0, "yellow": 0, "green": 0]
    for i in stride(from: 0, to: without.count, by: 4) {
        if abs(Int(withCursor[i]) - Int(without[i])) + abs(Int(withCursor[i + 1]) - Int(without[i + 1])) > 60 {
            diff += 1
        }
        let r = Int(without[i]), g = Int(without[i + 1]), b = Int(without[i + 2])
        if r > 230 && g < 30 && b > 230 { red += 1 }
        let hi = { (v: Int) in v > 230 }
        let lo = { (v: Int) in v < 30 }
        if hi(r) && lo(g) && hi(b) { colors["magenta"]! += 1 }
        if lo(r) && hi(g) && hi(b) { colors["cyan"]! += 1 }
        if hi(r) && hi(g) && lo(b) { colors["yellow"]! += 1 }
        if lo(r) && hi(g) && lo(b) { colors["green"]! += 1 }
    }
    let drawn = colors.filter { $0.value > 20 }.sorted { $0.value > $1.value }.map(\.key)
    print(
        "real=\(diff > 20 ? "yes" : "no") overlay=\(red > 20 ? "yes" : "no") color=\(drawn.first ?? "none") diffPx=\(diff) redPx=\(red) colors=\(colors.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))"
    )
case "cursor-set":
    // 背景プロセスから現在のカーソルを設定し続ける(overlay の形の追従を自動で確かめる用)。
    let name = args[0]
    let seconds = Double(args[1]) ?? 3
    let cid = mainConnection()
    _ = sym("CGSSetConnectionProperty", SetPropFn.self)!(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    let cursors: [String: NSCursor] = [
        "arrow": .arrow, "ibeam": .iBeam, "link": .pointingHand, "resize": .resizeLeftRight, "crosshair": .crosshair,
        "closedHand": .closedHand, "notAllowed": .operationNotAllowed,
    ]
    guard let cursor = cursors[name] else { fatalError("unknown cursor \(name)") }
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        cursor.set()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
case "pad":
    // 自動判定用の灰色の背景だけを出す(自前カーソルは描かない)
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let f = NSScreen.screens[0].frame
    let w = NSWindow(
        contentRect: NSRect(x: f.midX - 200, y: f.midY - 200, width: 400, height: 400), styleMask: [.borderless],
        backing: .buffered, defer: false)
    w.backgroundColor = NSColor(white: 0.5, alpha: 1)
    w.level = .floating
    w.ignoresMouseEvents = true
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    w.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(Double(args.first ?? "20") ?? 20))
case "table":
    for (name, c) in factoryCursors() {
        print("appkit\t\(name)\t\(cursorKey(c))\tsize=\(c.image.size) hot=\(c.hotSpot)")
    }
    for (name, key) in snapshotShapes() { print("snapshot\t\(name)\t\(key)") }
case "watch":
    buildShapeTable()
    let seconds = args.compactMap { Double($0) }.first ?? 10
    var last = ""
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        let s = status()
        if s != last { log(s); last = s }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
default:
    print(usage)
    exit(2)
}
