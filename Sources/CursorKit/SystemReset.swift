import CCursorBridge
import Foundation

/// スナップショットに頼らない最終手段。ポインター色のリセット時にシステムが行う再登録を、
/// 設定を書き換えずに呼び出す。戻る画像は「色リセット直後の標準」で、ログイン時の標準とは
/// ピクセル・hotspot が少し異なる(docs/PHASE0.md)。
public enum SystemReset {
    public struct Report: Sendable {
        public var before: [String: String]
        public var after: [String: String]
        /// リセット前は登録されていたのに、登録し直せなかった名前。
        public var failures: [String]
    }

    /// テーマの適用対象(ArrowS / IBeamS / com.apple.cursor.N)を OS の標準へ戻す。
    public static func run(store: SnapshotStore) throws -> Report {
        if CursorEnvironment.current().cursorIsCustomized == true {
            throw CursorKitError.busy(
                L10n.text(
                    "ポインターの色がカスタマイズされているため実行しない(標準色の画像を登録して色設定と食い違う)。システム設定 > アクセシビリティ > ディスプレイ > ポインタ で色を変更→戻すと、システムが登録し直す"
                )
            )
        }
        guard let axfUnregisterAll = CSResolveAXFCursorUnregisterAll() else {
            throw CursorKitError.symbolMissing("AXFCursorUnregisterAll(AccessibilityFoundation)")
        }
        let symbols = CSResolveSymbols()
        guard let main = symbols.mainConnectionID else { throw CursorKitError.symbolMissing("CGSMainConnectionID") }
        guard let coreUnregisterAll = symbols.coreCursorUnregisterAll else {
            throw CursorKitError.symbolMissing("CoreCursorUnregisterAll")
        }
        guard let coreCursorSet = symbols.coreCursorSet else { throw CursorKitError.symbolMissing("CoreCursorSet") }
        let cid = main()
        let backend = try CGSBackend()
        let names = CursorCatalog.snapshotNames
        let before = try Dictionary(uniqueKeysWithValues: names.map { ($0, try backend.read($0).hash) })

        axfUnregisterAll()
        let err = coreUnregisterAll(cid)
        guard err == 0 else { throw CursorKitError.backend(operation: "CoreCursorUnregisterAll", name: "-", code: err) }
        // 未登録のままだと、すでにそのカーソルを使ったアプリは名前で設定し続けて矢印になる
        // (指差しで実測)。CoreCursorSet で HIServices に標準画像を登録し直させる。
        var failures: [String] = []
        for id in CursorCatalog.coreCursorIDs where id >= 2 {
            let name = CursorCatalog.coreCursorPrefix + String(id)
            let setErr = coreCursorSet(cid, Int32(id))
            let registered = try backend.read(name).rep != nil
            if before[name] != "-", setErr != 0 || !registered {
                failures.append("\(name)(CoreCursorSet err=\(setErr))")
            }
        }
        // 上のループで自プロセスのカーソルが最後の ID になっているので矢印に戻す。自プロセスだけの話なので失敗は無視する。
        _ = coreCursorSet(cid, 0)

        let after = try Dictionary(uniqueKeysWithValues: names.map { ($0, try backend.read($0).hash) })
        if failures.isEmpty { try store.saveJournal(.clean) }
        return Report(before: before, after: after, failures: failures)
    }
}
