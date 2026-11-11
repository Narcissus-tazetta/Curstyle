import CCursorBridge
import CoreGraphics
import Foundation

public enum ReadResult: Sendable {
    case registered(CursorRep)
    case unregistered

    public var rep: CursorRep? {
        if case .registered(let r) = self { return r }
        return nil
    }

    /// 未登録は "-" として、登録済みと同じ土俵で比較できるようにする。
    public var hash: String { rep?.contentHash ?? "-" }
}

public protocol CursorBackend {
    func read(_ name: String) throws -> ReadResult
    func register(_ name: String, _ rep: CursorRep) throws
    func remove(_ name: String) throws
    /// com.apple.cursor.<id> を HIServices 内蔵の標準画像で登録させる(未登録のときだけ登録される)。
    func registerSystemDefault(coreCursorID id: Int) throws
}

/// 非公開 CGS/CoreCursor API の経路。シンボルは dlsym で解決し、欠けていれば初期化で失敗する。
public final class CGSBackend: CursorBackend {
    /// CGSCopyRegisteredCursorImages が未登録の名前に返す値(Phase 0 で実測)。
    static let errNotRegistered: Int32 = 1007

    let cid: CSConnectionID
    let copyFn: CSCopyRegisteredCursorImagesFn
    let registerFn: CSRegisterCursorWithImagesFn
    let removeFn: CSRemoveRegisteredCursorFn
    let symbols: CSSymbols

    public init() throws {
        symbols = CSResolveSymbols()
        guard let main = symbols.mainConnectionID else { throw CursorKitError.symbolMissing("CGSMainConnectionID") }
        guard let copy = symbols.copyRegisteredCursorImages else {
            throw CursorKitError.symbolMissing("CGSCopyRegisteredCursorImages")
        }
        guard let reg = symbols.registerCursorWithImages else {
            throw CursorKitError.symbolMissing("CGSRegisterCursorWithImages")
        }
        guard let rem = symbols.removeRegisteredCursor else {
            throw CursorKitError.symbolMissing("CGSRemoveRegisteredCursor")
        }
        cid = main()
        copyFn = copy
        registerFn = reg
        removeFn = rem
    }

    public func read(_ name: String) throws -> ReadResult {
        var size = CGSize.zero
        var hot = CGPoint.zero
        var frames: UInt = 0
        var dur: CGFloat = 0
        var arr: Unmanaged<CFArray>?
        let err = name.withCString { copyFn(cid, $0, &size, &hot, &frames, &dur, &arr) }
        if err == Self.errNotRegistered { return .unregistered }
        guard err == 0 else {
            throw CursorKitError.backend(operation: "CGSCopyRegisteredCursorImages", name: name, code: err)
        }
        guard let array = arr?.takeRetainedValue() else {
            throw CursorKitError.backend(
                operation: L10n.text("CGSCopyRegisteredCursorImages(画像配列が NULL)"), name: name, code: err)
        }
        var images: [CGImage] = []
        for obj in array as [AnyObject] {
            guard CFGetTypeID(obj) == CGImage.typeID else {
                throw CursorKitError.backend(
                    operation: L10n.text("CGSCopyRegisteredCursorImages(CGImage 以外が入っている)"), name: name, code: err)
            }
            images.append(obj as! CGImage)
        }
        return .registered(
            CursorRep(size: size, hotspot: hot, frameCount: Int(frames), frameDuration: Double(dur), images: images))
    }

    public func register(_ name: String, _ rep: CursorRep) throws {
        var seed: Int32 = 0
        let err = name.withCString {
            registerFn(
                cid, $0, true, true, rep.size, rep.hotspot, UInt(rep.frameCount), CGFloat(rep.frameDuration),
                rep.images as CFArray, &seed)
        }
        guard err == 0 else {
            throw CursorKitError.backend(operation: "CGSRegisterCursorWithImages", name: name, code: err)
        }
    }

    public func remove(_ name: String) throws {
        let err = name.withCString { removeFn(cid, $0, true) }
        guard err == 0 else {
            throw CursorKitError.backend(operation: "CGSRemoveRegisteredCursor", name: name, code: err)
        }
    }

    public func registerSystemDefault(coreCursorID id: Int) throws {
        guard let set = symbols.coreCursorSet else { throw CursorKitError.symbolMissing("CoreCursorSet") }
        let err = set(cid, Int32(id))
        // CoreCursorSet は自プロセスのカーソルも切り替えるので矢印に戻す。自プロセスだけの話なので失敗は無視する。
        _ = set(cid, 0)
        guard err == 0 else {
            throw CursorKitError.backend(
                operation: "CoreCursorSet", name: CursorCatalog.coreCursorPrefix + String(id), code: err)
        }
    }

    /// SkyLight 内の固定表。識別子の自動発見には使えないが、OS 更新で表が増えたことの検知には使える。
    public func systemCursorTable() -> [Int32: String] {
        guard let fn = symbols.cursorNameForSystemCursor else { return [:] }
        var table: [Int32: String] = [:]
        for id in Int32(0)..<512 {
            if let p = fn(id) { table[id] = String(cString: p) }
        }
        return table
    }

    public func cursorScale() -> Float? {
        guard let fn = symbols.getCursorScale else { return nil }
        var scale: Float = 0
        return fn(cid, &scale) == 0 ? scale : nil
    }
}

/// 失敗注入用。n 回成功した後の register を1回だけ失敗させる(一時的な失敗。ロールバック自体は通る)、
/// または n 回目の後にプロセスを強制終了する。
public final class FaultInjectingBackend: CursorBackend {
    public enum Fault: Sendable {
        case failRegister(after: Int)
        case killProcess(after: Int)
    }

    let base: CursorBackend
    let fault: Fault
    private var registers = 0
    private var injected = false

    public init(base: CursorBackend, fault: Fault) {
        self.base = base
        self.fault = fault
    }

    public func read(_ name: String) throws -> ReadResult { try base.read(name) }
    public func remove(_ name: String) throws { try base.remove(name) }
    public func registerSystemDefault(coreCursorID id: Int) throws { try base.registerSystemDefault(coreCursorID: id) }

    public func register(_ name: String, _ rep: CursorRep) throws {
        if case .failRegister(let n) = fault, registers >= n, !injected {
            injected = true
            throw CursorKitError.injectedFailure(
                L10n.text("{0} 回目の register({1})", String(describing: registers + 1), String(describing: name)))
        }
        try base.register(name, rep)
        registers += 1
        if case .killProcess(let n) = fault, registers >= n {
            FileHandle.standardError.write(
                Data(L10n.text("注入: {0} 回目の register 後に SIGKILL\n", String(describing: registers)).utf8))
            kill(getpid(), SIGKILL)
        }
    }
}
