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
            report.add(.ok, "ポインターのサイズ", "\(size)(標準は 1)。テーマ適用後に変えると OS が cursor.N のテーマを消す。変更後の `curstyle apply` は有効")
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
            for s in states where s.state == .themed {
                report.add(.ok, s.name, "\(s.state.rawValue) hash=\(s.hash)")
            }
            // 再ログイン・再起動・ポインターサイズ変更で OS がテーマの画像を消しても、ジャーナルは applied のまま残る。
            if journal.status == .applied {
                let themed = Set(states.filter { $0.state == .themed }.map(\.name))
                let lost = journal.intended.keys.filter { !themed.contains($0) }
                if !lost.isEmpty {
                    report.add(
                        .warning, "テーマが消えている",
                        "ジャーナルは適用中だが、\(journal.intended.count) 件のうち \(lost.count) 件はテーマの画像が登録されていない(再ログイン・再起動・ポインターサイズ変更で OS が消す)。`curstyle apply <テーマ>` で再適用するか、`curstyle restore` で標準へ戻してジャーナルを clean にできる"
                    )
                }
            }
            // 色のカスタマイズ中・リセット直後は、システムが ArrowS / IBeamS / cursor.13 を登録し直すので「不明」になる。
            // カスタマイズ中に restore すると色設定と食い違う画像を登録するので勧めない。
            let unknownHint =
                env.cursorIsCustomized == true
                ? "ポインター色のカスタマイズでシステムが登録した画像と見られる(想定どおり)"
                : "他のカーソルアプリかポインター設定の変更で書き換わった可能性がある。ポインター色を戻した直後なら `curstyle snapshot` で取り直す。それ以外は `curstyle restore` で取得時の標準へ戻せる"
            for s in states where s.state == .unknown {
                report.add(.warning, s.name, "\(s.state.rawValue) hash=\(s.hash)。\(unknownHint)")
            }
        } catch {
            report.add(.error, "状態の読み取り", "\(error)")
        }
        report.add(.ok, "注意", "読み戻しの一致は画面に表示された証拠ではない。表示は目視で確認すること")
        return report
    }
}

extension Diagnostics {
    /// 不具合報告に添付する全文。自己診断に加えて、OS が返した生の値を残す。
    /// ホームディレクトリのパスは ~ に置き換える(ユーザー名を含めない)。
    public static func fullReport(store: SnapshotStore) -> String {
        var out: [String] = []
        func section(_ title: String) { out.append("\n## \(title)") }

        out.append("# curstyle 診断レポート")
        out.append("生成: \(ISO8601DateFormatter().string(from: Date()))")
        out.append("OS: macOS \(CursorEnvironment.current().osVersion) (\(sysctlString("kern.osversion") ?? "?"))")
        out.append("機種: \(sysctlString("hw.model") ?? "?") / \(sysctlString("hw.machine") ?? "?")")

        section("自己診断")
        for item in run(store: store).items {
            out.append("[\(item.level.rawValue)] \(item.title): \(item.detail)")
        }

        section("ポインター設定 (com.apple.universalaccess)")
        let domain = "com.apple.universalaccess" as CFString
        let keys =
            (CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]) ?? []
        let cursorKeys = keys.filter { $0.lowercased().contains("cursor") }.sorted()
        if cursorKeys.isEmpty { out.append("(cursor を含むキーなし)") }
        for key in cursorKeys {
            let value = CFPreferencesCopyAppValue(key as CFString, domain).map { "\($0)" } ?? "nil"
            out.append("\(key) = \(value.replacingOccurrences(of: "\n", with: " "))")
        }

        section("シンボル")
        _ = CSResolveAXFCursorUnregisterAll()
        for symbol in requiredSymbols + optionalSymbols + [
            "CoreCursorSet", "CoreCursorCopyImages", "AXFCursorUnregisterAll",
        ] {
            out.append("\(symbol): \(CSImagePathForSymbol(symbol).map { String(cString: $0) } ?? "欠落")")
        }

        let backend: CGSBackend
        do {
            backend = try CGSBackend()
        } catch {
            out.append("\nバックエンドを初期化できない: \(error)")
            return redactHome(out.joined(separator: "\n"))
        }

        section("CGSCursorNameForSystemCursor")
        let table = backend.systemCursorTable()
        if table.isEmpty { out.append("(取得できない)") }
        for (id, name) in table.sorted(by: { $0.key < $1.key }) {
            let mark = CursorCatalog.knownSystemCursorTable[id] == name ? "" : "  ← macOS 27.2 の表と異なる"
            out.append("\(id): \(name)\(mark)")
        }

        section("名前ごとの状態")
        do {
            let states = try CursorEngine(backend: backend, store: store).states()
            for s in states {
                let summary = try backend.read(s.name).rep?.summary ?? "未登録"
                out.append("\(s.name)\t\(s.state.rawValue)\t\(s.hash)\t\(summary)")
            }
        } catch {
            out.append("読み取れない: \(error)")
        }

        section("ジャーナル")
        if FileManager.default.fileExists(atPath: store.journalURL.path) {
            do {
                out.append(try String(contentsOf: store.journalURL, encoding: .utf8))
            } catch {
                out.append("読めない: \(error)")
            }
        } else {
            out.append("(無い = clean)")
        }

        section("スナップショット")
        do {
            if let manifest = try store.loadManifest() {
                out.append(
                    "更新: \(ISO8601DateFormatter().string(from: manifest.updatedAt)) 件数: \(manifest.entries.count)")
                let byEnv = Dictionary(grouping: manifest.entries, by: \.value.environment)
                for (env, entries) in byEnv.sorted(by: { $0.value.count > $1.value.count }) {
                    out.append(
                        "取得時の環境 os=\(env.osVersion) cursorIsCustomized=\(env.cursorIsCustomized.map { "\($0)" } ?? "nil") size=\(env.cursorSize.map { "\($0)" } ?? "nil"): \(entries.count) 件"
                    )
                }
            } else {
                out.append("(無い)")
            }
        } catch {
            out.append("読めない: \(error)")
        }
        return redactHome(out.joined(separator: "\n")) + "\n"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func redactHome(_ text: String) -> String {
        text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
