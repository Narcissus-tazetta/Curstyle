import CCursorBridge
import Foundation

public struct DiagnosticReport: Sendable {
    public enum Level: String, Sendable {
        case ok = "OK"
        case warning = "注意"
        case error = "問題"
    }

    public struct Item: Sendable {
        public var level: Level
        public var title: String
        public var detail: String
    }

    public var items: [Item] = []
    public var hasProblem: Bool { items.contains { $0.level != .ok } }

    mutating func add(_ level: Level, _ title: String, _ detail: String) {
        items.append(Item(level: level, title: title, detail: detail))
    }
}

public enum Diagnostics {
    static let requiredSymbols = [
        "CGSMainConnectionID", "CGSRegisterCursorWithImages", "CGSCopyRegisteredCursorImages",
        "CGSRemoveRegisteredCursor",
    ]
    static let optionalSymbols = ["CGSCursorNameForSystemCursor", "CGSGetCursorScale", "CoreCursorUnregisterAll"]

    public static func run(store: SnapshotStore) -> DiagnosticReport {
        var report = DiagnosticReport()
        let env = CursorEnvironment.current()
        report.add(.ok, "OS", "macOS \(env.osVersion)")

        for s in requiredSymbols where CSImagePathForSymbol(s) == nil {
            report.add(.error, "シンボル欠落", "\(s) が無い。この OS ではカーソルを変更できない")
        }
        for s in optionalSymbols where CSImagePathForSymbol(s) == nil {
            report.add(.warning, "シンボル欠落", "\(s) が無い(診断の一部が使えない)")
        }
        if CSResolveAXFCursorUnregisterAll() == nil || CSImagePathForSymbol("CoreCursorSet") == nil {
            report.add(.warning, "reset-system", "AXFCursorUnregisterAll か CoreCursorSet が無い。スナップショットなしでは標準へ戻せない")
        }

        switch env.cursorIsCustomized {
        case true?:
            report.add(
                .error, "ポインターの色",
                "カスタマイズされている(cursorIsCustomized=1)。この状態ではテーマは画面に表示されない。システム設定 > アクセシビリティ > ディスプレイ > ポインタ で色をリセットすること")
        case false?: report.add(.ok, "ポインターの色", "標準")
        case nil: report.add(.warning, "ポインターの色", "cursorIsCustomized を読めない")
        }
        if let size = env.cursorSize, size != 1 {
            report.add(.warning, "ポインターのサイズ", "\(size)(標準は 1)。サイズ変更時の挙動は未確認")
        }

        let backend: CGSBackend
        do {
            backend = try CGSBackend()
        } catch {
            report.add(.error, "バックエンド", "\(error)")
            return report
        }
        if let scale = backend.cursorScale() {
            report.add(.ok, "CGSGetCursorScale", "\(scale)")
        }

        let table = backend.systemCursorTable()
        if !table.isEmpty, table != CursorCatalog.knownSystemCursorTable {
            let added = table.filter { CursorCatalog.knownSystemCursorTable[$0.key] != $0.value }
            let removed = CursorCatalog.knownSystemCursorTable.filter { table[$0.key] != $0.value }
            report.add(
                .warning, "識別子の表が変わった",
                "CGSCursorNameForSystemCursor が macOS 27.2 と異なる。追加/変更: \(added.sorted { $0.key < $1.key }) 消えた: \(removed.sorted { $0.key < $1.key })。表に無い名前は標準のまま残る"
            )
        }

        do {
            let journal = try store.loadJournal()
            report.add(
                .ok, "ジャーナル",
                "\(journal.status.rawValue) theme=\(journal.themeName ?? "-") 対象=\(journal.intended.count)")
            if journal.status == .applying {
                report.add(.error, "適用が途中で止まっている", "前回の適用が完了していない。`curstyle restore` で標準へ戻せる")
            }
            if let manifest = try store.loadManifest() {
                report.add(.ok, "スナップショット", "\(manifest.entries.count) 件 更新 \(manifest.updatedAt)")
                let envs = Set(manifest.entries.values.map(\.environment))
                if envs.contains(where: { $0.cursorIsCustomized == true }) {
                    report.add(.warning, "スナップショット", "ポインター色カスタマイズ中に取得した標準画像を含む")
                }
            } else {
                report.add(
                    .warning, "スナップショット",
                    journal.intended.isEmpty
                        ? "まだ無い(初回適用時に取得する)" : "無いのにテーマ適用の記録がある。`curstyle reset-system` で OS の標準へ戻すこと")
            }
            let engine = CursorEngine(backend: backend, store: store)
            let states = try engine.states()
            let counts = Dictionary(grouping: states, by: \.state).mapValues(\.count)
            report.add(.ok, "名前ごとの状態", counts.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: " "))
            for s in states where s.state == .themed || s.state == .unknown {
                report.add(s.state == .unknown ? .warning : .ok, s.name, "\(s.state.rawValue) hash=\(s.hash)")
            }
        } catch {
            report.add(.error, "状態の読み取り", "\(error)")
        }
        report.add(.ok, "注意", "読み戻しの一致は画面に表示された証拠ではない。表示は目視で確認すること")
        return report
    }
}
