import Foundation

/// OverlayBackend が使う非公開シンボル。docs/PHASE3_5.md で動作を確かめたもの。
/// 1つでも欠けていれば overlay は使えない(初期化で失敗し、診断に出す)。
public struct OverlaySymbols: @unchecked Sendable {
    typealias ConnectionFn = @convention(c) () -> Int32
    typealias SetPropertyFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    typealias CursorFn = @convention(c) (Int32) -> Int32
    typealias SeedFn = @convention(c) () -> Int32
    typealias VisibleFn = @convention(c) () -> UInt32
    typealias ScaleFn = @convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32

    public static let names = [
        "CGSMainConnectionID", "CGSSetConnectionProperty", "CGSHideCursor", "CGSShowCursor", "CGSCurrentCursorSeed",
        "CGCursorIsVisible",
    ]

    let mainConnection: ConnectionFn
    let setProperty: SetPropertyFn
    let hideCursor: CursorFn
    let showCursor: CursorFn
    let cursorSeed: SeedFn
    let cursorIsVisible: VisibleFn
    let getCursorScale: ScaleFn?
    let getBackgroundEventMask: GetMaskFn?
    let setBackgroundEventMask: SetMaskFn?

    typealias GetMaskFn = @convention(c) (Int32, UnsafeMutablePointer<UInt32>) -> Int32
    typealias SetMaskFn = @convention(c) (Int32, UInt32) -> Int32

    public static func missing() -> [String] {
        names.filter { lookup($0) == nil }
    }

    public init() throws {
        func need<T>(_ name: String, _: T.Type) throws -> T {
            guard let p = Self.lookup(name) else { throw CursorKitError.symbolMissing(name) }
            return unsafeBitCast(p, to: T.self)
        }
        mainConnection = try need("CGSMainConnectionID", ConnectionFn.self)
        setProperty = try need("CGSSetConnectionProperty", SetPropertyFn.self)
        hideCursor = try need("CGSHideCursor", CursorFn.self)
        showCursor = try need("CGSShowCursor", CursorFn.self)
        cursorSeed = try need("CGSCurrentCursorSeed", SeedFn.self)
        // Swift からは unavailable 扱いだが、シンボルは残っている(macOS 27.2)。
        cursorIsVisible = try need("CGCursorIsVisible", VisibleFn.self)
        getCursorScale = Self.lookup("CGSGetCursorScale").map { unsafeBitCast($0, to: ScaleFn.self) }
        getBackgroundEventMask = Self.lookup("SLSGetBackgroundEventMask").map { unsafeBitCast($0, to: GetMaskFn.self) }
        setBackgroundEventMask = Self.lookup("SLSSetBackgroundEventMask").map { unsafeBitCast($0, to: SetMaskFn.self) }
    }

    // dlopen のハンドルは読み取り専用で使う。
    nonisolated(unsafe) private static let skyLight = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func lookup(_ name: String) -> UnsafeMutableRawPointer? {
        if let skyLight, let p = dlsym(skyLight, name) { return p }
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)  // RTLD_DEFAULT
    }

    var isCursorVisible: Bool { cursorIsVisible() != 0 }

    /// バックグラウンドのプロセスに届くイベントの種類。取れなければ nil。
    func backgroundEventMask(_ cid: Int32) -> UInt32? {
        guard let getBackgroundEventMask else { return nil }
        var mask: UInt32 = 0
        return getBackgroundEventMask(cid, &mask) == 0 ? mask : nil
    }

    func cursorScale(_ cid: Int32) -> CGFloat {
        guard let getCursorScale else { return 1 }
        var scale: Float = 1
        return getCursorScale(cid, &scale) == 0 && scale > 0 ? CGFloat(scale) : 1
    }
}
