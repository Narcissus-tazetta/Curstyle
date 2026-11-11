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
            report.add(
                .error, L10n.text("シンボル欠落"),
                L10n.text("{0} が無い。この OS では CGSBackend でカーソルを変更できない", String(describing: s)))
        }
        for s in optionalSymbols where CSImagePathForSymbol(s) == nil {
            report.add(.warning, L10n.text("シンボル欠落"), L10n.text("{0} が無い(診断の一部が使えない)", String(describing: s)))
        }
        if CSResolveAXFCursorUnregisterAll() == nil || CSImagePathForSymbol("CoreCursorSet") == nil {
            report.add(
                .warning, "reset-system", L10n.text("AXFCursorUnregisterAll か CoreCursorSet が無い。スナップショットなしでは標準へ戻せない"))
        }

        switch env.cursorIsCustomized {
        case true?:
            report.add(
                .error, L10n.text("ポインターの色"),
                L10n.text(
                    "カスタマイズされている(cursorIsCustomized=1)。この状態ではテーマは画面に表示されない。システム設定 > アクセシビリティ > ディスプレイ > ポインタ で色をリセットすること"
                ))
        case false?: report.add(.ok, L10n.text("ポインターの色"), L10n.text("標準"))
        case nil: report.add(.warning, L10n.text("ポインターの色"), L10n.text("cursorIsCustomized を読めない"))
        }
        if let size = env.cursorSize, size != 1 {
            report.add(
                .ok, L10n.text("ポインターのサイズ"),
                L10n.text(
                    "{0}(標準は 1)。テーマ適用後に変えると OS が cursor.N のテーマを消す。変更後の `curstyle apply` は有効", String(describing: size)))
        }

        let overlayMissing = OverlaySymbols.missing()
        if overlayMissing.isEmpty {
            report.add(.ok, L10n.text("overlay 方式"), L10n.text("使える(`curstyle apply --backend overlay <テーマ>`)"))
        } else {
            report.add(
                .warning, L10n.text("overlay 方式"),
                L10n.text("シンボル {0} が無いため使えない", String(describing: overlayMissing.joined(separator: ", "))))
        }
        addOverlayStatus(&report, store: store)

        let backend: CGSBackend
        do {
            backend = try CGSBackend()
        } catch {
            report.add(
                .error, L10n.text("バックエンド"),
                "\(error)\(overlayMissing.isEmpty ? L10n.text("。CGSBackend が使えないので、overlay 方式(`curstyle apply --backend overlay <テーマ>`)を使える") : "")"
            )
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
                .warning, L10n.text("識別子の表が変わった"),
                L10n.text(
                    "CGSCursorNameForSystemCursor が macOS 27.2 と異なる。追加/変更: {0} 消えた: {1}。表に無い名前は標準のまま残る",
                    String(describing: added.sorted { $0.key < $1.key }),
                    String(describing: removed.sorted { $0.key < $1.key }))
            )
        }

        do {
            let journal = try store.loadJournal()
            report.add(
                .ok, L10n.text("ジャーナル"),
                L10n.text(
                    "{0} backend={1} theme={2} 対象={3}", String(describing: journal.status.rawValue),
                    String(describing: journal.backend.rawValue), String(describing: journal.themeName ?? "-"),
                    String(describing: journal.intended.count))
            )
            if journal.status == .applying {
                report.add(.error, L10n.text("適用が途中で止まっている"), L10n.text("前回の適用が完了していない。`curstyle restore` で標準へ戻せる"))
            }
            if let manifest = try store.loadManifest() {
                report.add(
                    .ok, L10n.text("スナップショット"),
                    L10n.text(
                        "{0} 件 更新 {1}", String(describing: manifest.entries.count),
                        String(describing: manifest.updatedAt)))
                let envs = Set(manifest.entries.values.map(\.environment))
                if envs.contains(where: { $0.cursorIsCustomized == true }) {
                    report.add(.warning, L10n.text("スナップショット"), L10n.text("ポインター色カスタマイズ中に取得した標準画像を含む"))
                }
            } else {
                report.add(
                    .warning, L10n.text("スナップショット"),
                    journal.intended.isEmpty
                        ? L10n.text("まだ無い(初回適用時に取得する)")
                        : L10n.text("無いのにテーマ適用の記録がある。`curstyle reset-system` で OS の標準へ戻すこと"))
            }
            let engine = CursorEngine(backend: backend, store: store)
            let states = try engine.states()
            let counts = Dictionary(grouping: states, by: \.state).mapValues(\.count)
            report.add(
                .ok, L10n.text("名前ごとの状態"),
                counts.map { "\(L10n.text($0.key.rawValue))=\($0.value)" }.sorted().joined(separator: " "))
            for s in states where s.state == .themed {
                report.add(.ok, s.name, "\(L10n.text(s.state.rawValue)) hash=\(s.hash)")
            }
            // 再ログイン・再起動・ポインターサイズ変更で OS がテーマの画像を消しても、ジャーナルは applied のまま残る。
            if journal.status == .applied {
                let themed = Set(states.filter { $0.state == .themed }.map(\.name))
                let lost = journal.intended.keys.filter { !themed.contains($0) }
                if !lost.isEmpty {
                    report.add(
                        .warning, L10n.text("テーマが消えている"),
                        L10n.text(
                            "ジャーナルは適用中だが、{0} 件のうち {1} 件はテーマの画像が登録されていない(再ログイン・再起動・ポインターサイズ変更で OS が消す)。`curstyle apply <テーマ>` で再適用するか、`curstyle restore` で標準へ戻してジャーナルを clean にできる",
                            String(describing: journal.intended.count), String(describing: lost.count))
                    )
                }
            }
            let renewed = states.filter { $0.state == .renewedAtLogin }.map(\.name)
            if !renewed.isEmpty {
                report.add(
                    .ok, L10n.text("ログイン時に更新された標準"),
                    L10n.text(
                        "{0} はスナップショット取得後のログインで OS が別の標準を登録した。このまま `curstyle restore` するとログイン前の標準で上書きするので、先に `curstyle snapshot` で取り直すこと(apply と自動再適用は取り直してから適用する)",
                        String(describing: renewed.joined(separator: ", ")))
                )
            }
            // 色のカスタマイズ中・リセット直後は、システムが ArrowS / IBeamS / cursor.13 を登録し直すので「不明」になる。
            // カスタマイズ中に restore すると色設定と食い違う画像を登録するので勧めない。
            let unknownHint =
                env.cursorIsCustomized == true
                ? L10n.text("ポインター色のカスタマイズでシステムが登録した画像と見られる(想定どおり)")
                : L10n.text(
                    "他のカーソルアプリかポインター設定の変更で書き換わった可能性がある。ポインター色を戻した直後なら `curstyle snapshot` で取り直す。それ以外は `curstyle restore` で取得時の標準へ戻せる"
                )
            for s in states where s.state == .unknown {
                report.add(.warning, s.name, "\(L10n.text(s.state.rawValue)) hash=\(s.hash)。\(unknownHint)")
            }
        } catch {
            report.add(.error, L10n.text("状態の読み取り"), "\(error)")
        }
        do {
            let helper = try store.loadHelperState()
            if let reason = helper.stoppedReason {
                report.add(
                    .warning, L10n.text("自動再適用ヘルパー"),
                    L10n.text(
                        "停止中: {0}。原因を確かめてから `curstyle helper resume`(apply / restore でも再開する)",
                        String(describing: reason)))
            } else if let last = helper.lastCheckAt {
                report.add(
                    .ok, L10n.text("自動再適用ヘルパー"),
                    L10n.text("直近の確認 {0}: {1}", String(describing: last), String(describing: helper.lastResult ?? "-")))
            }
        } catch {
            report.add(.warning, L10n.text("自動再適用ヘルパー"), L10n.text("helper.json を読めない: {0}", String(describing: error)))
        }
        report.add(.ok, L10n.text("注意"), L10n.text("読み戻しの一致は画面に表示された証拠ではない。表示は目視で確認すること"))
        return report
    }
}

extension Diagnostics {
    static func addOverlayStatus(_ report: inout DiagnosticReport, store: SnapshotStore) {
        guard let journal = try? store.loadJournal(), journal.backend == .overlay, journal.status == .applied else {
            return
        }
        let status = (try? store.loadHelperState())?.overlay
        guard let status, status.running else {
            report.add(
                .error, "overlay",
                L10n.text(
                    "overlay 方式で適用中だが、ヘルパーが描画していない{0}。`curstyle helper status` を確認し、未インストールなら `curstyle helper install`。`curstyle restore` で解除できる",
                    String(describing: status?.stoppedReason.map { "(\($0))" } ?? ""))
            )
            return
        }
        report.add(
            .ok, "overlay",
            L10n.text(
                "描画中 theme={0} 開始 {1} 照合表 {2} 件", String(describing: status.themeName ?? "-"),
                String(describing: status.startedAt.map { "\($0)" } ?? "-"), String(describing: status.matcherEntries))
        )
        if status.yieldCount > 0 {
            let scenes = status.yieldScenes.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            report.add(
                .ok, L10n.text("overlay: 本物を隠せなかった場面"),
                L10n.text(
                    "{0} 回(その間は標準カーソルを表示。最前面アプリ別: {1})。Mission Control・Command+Shift+4・Dock の上では想定どおり",
                    String(describing: status.yieldCount), String(describing: scenes))
            )
        }
        if status.unknownShapes > 0 {
            report.add(
                .ok, L10n.text("overlay: 照合できなかった形"),
                L10n.text("{0} 種類(標準の見た目のまま描いた。アプリ独自のカーソルやスクリーンショットの十字など)", String(describing: status.unknownShapes)))
        }
    }

    /// 不具合報告に添付する全文。自己診断に加えて、OS が返した生の値を残す。
    /// ホームディレクトリのパスは ~ に置き換える(ユーザー名を含めない)。
    public static func fullReport(store: SnapshotStore) -> String {
        var out: [String] = []
        func section(_ title: String) { out.append("\n## \(title)") }

        out.append(L10n.text("# curstyle 診断レポート"))
        out.append(L10n.text("生成: {0}", String(describing: ISO8601DateFormatter().string(from: Date()))))
        out.append("OS: macOS \(CursorEnvironment.current().osVersion) (\(sysctlString("kern.osversion") ?? "?"))")
        out.append(
            L10n.text(
                "機種: {0} / {1}", String(describing: sysctlString("hw.model") ?? "?"),
                String(describing: sysctlString("hw.machine") ?? "?")))

        section(L10n.text("自己診断"))
        for item in run(store: store).items {
            out.append("[\(L10n.text(item.level.rawValue))] \(item.title): \(item.detail)")
        }

        section(L10n.text("ポインター設定 (com.apple.universalaccess)"))
        let domain = "com.apple.universalaccess" as CFString
        let keys =
            (CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]) ?? []
        let cursorKeys = keys.filter { $0.lowercased().contains("cursor") }.sorted()
        if cursorKeys.isEmpty { out.append(L10n.text("(cursor を含むキーなし)")) }
        for key in cursorKeys {
            let value = CFPreferencesCopyAppValue(key as CFString, domain).map { "\($0)" } ?? "nil"
            out.append("\(key) = \(value.replacingOccurrences(of: "\n", with: " "))")
        }

        section(L10n.text("シンボル"))
        _ = CSResolveAXFCursorUnregisterAll()
        for symbol in requiredSymbols + optionalSymbols + [
            "CoreCursorSet", "CoreCursorCopyImages", "AXFCursorUnregisterAll",
        ] {
            out.append("\(symbol): \(CSImagePathForSymbol(symbol).map { String(cString: $0) } ?? L10n.text("欠落"))")
        }

        let backend: CGSBackend
        do {
            backend = try CGSBackend()
        } catch {
            out.append(L10n.text("\nバックエンドを初期化できない: {0}", String(describing: error)))
            return redactHome(out.joined(separator: "\n"))
        }

        section("CGSCursorNameForSystemCursor")
        let table = backend.systemCursorTable()
        if table.isEmpty { out.append(L10n.text("(取得できない)")) }
        for (id, name) in table.sorted(by: { $0.key < $1.key }) {
            let mark = CursorCatalog.knownSystemCursorTable[id] == name ? "" : L10n.text("  ← macOS 27.2 の表と異なる")
            out.append("\(id): \(name)\(mark)")
        }

        section(L10n.text("名前ごとの状態"))
        do {
            let states = try CursorEngine(backend: backend, store: store).states()
            for s in states {
                let summary = try backend.read(s.name).rep?.summary ?? L10n.text("未登録")
                out.append("\(s.name)\t\(L10n.text(s.state.rawValue))\t\(s.hash)\t\(summary)")
            }
        } catch {
            out.append(L10n.text("読み取れない: {0}", String(describing: error)))
        }

        section(L10n.text("ジャーナル"))
        if FileManager.default.fileExists(atPath: store.journalURL.path) {
            do {
                out.append(try String(contentsOf: store.journalURL, encoding: .utf8))
            } catch {
                out.append(L10n.text("読めない: {0}", String(describing: error)))
            }
        } else {
            out.append(L10n.text("(無い = clean)"))
        }

        section(L10n.text("スナップショット"))
        do {
            if let manifest = try store.loadManifest() {
                out.append(
                    L10n.text(
                        "更新: {0} 件数: {1}", String(describing: ISO8601DateFormatter().string(from: manifest.updatedAt)),
                        String(describing: manifest.entries.count)))
                let byEnv = Dictionary(grouping: manifest.entries, by: \.value.environment)
                for (env, entries) in byEnv.sorted(by: { $0.value.count > $1.value.count }) {
                    out.append(
                        L10n.text(
                            "取得時の環境 os={0} cursorIsCustomized={1} size={2}: {3} 件", String(describing: env.osVersion),
                            String(describing: env.cursorIsCustomized.map { "\($0)" } ?? "nil"),
                            String(describing: env.cursorSize.map { "\($0)" } ?? "nil"),
                            String(describing: entries.count))
                    )
                }
            } else {
                out.append(L10n.text("(無い)"))
            }
        } catch {
            out.append(L10n.text("読めない: {0}", String(describing: error)))
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
