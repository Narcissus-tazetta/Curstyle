import Foundation

public struct NameResult: Sendable {
    public enum Outcome: String, Sendable {
        case applied = "適用"
        case restored = "復元"
        case removed = "削除"
        case unchanged = "変更なし"
        case failed = "失敗"
    }

    public var name: String
    public var outcome: Outcome
    /// 読み戻したハッシュが期待値と一致したか。表示されたことの証拠ではない。
    public var readbackMatches: Bool
    public var detail: String?
}

public struct ApplyReport: Sendable {
    public var themeName: String
    public var environment: CursorEnvironment
    public var results: [NameResult]
    /// 失敗したときの原因と、ロールバックの結果。
    public var failure: String?
    public var rollback: RestoreReport?
    public var succeeded: Bool { failure == nil }
}

public struct RestoreReport: Sendable {
    public var results: [NameResult]
    public var succeeded: Bool { results.allSatisfy { $0.outcome != .failed && $0.readbackMatches } }
}

/// 名前ごとの現状。適用中かどうかは登録 API の戻り値ではなく、スナップショットとジャーナルとの比較で判定する。
public enum NameState: String, Sendable {
    case standard = "標準(スナップショット一致)"
    case themed = "テーマ適用中"
    case unregistered = "未登録(アプリが使うときに OS が標準を登録する)"
    case renewedAtLogin = "標準(ログイン時に OS が登録し直した。スナップショットはそれより前)"
    case unknown = "不明(スナップショットとも適用内容とも異なる)"
    case noSnapshot = "スナップショットなし"
}

/// スナップショットからの復元。テーマのコードには依存しない、最小の独立経路。
public struct Recovery {
    let backend: CursorBackend
    let store: SnapshotStore

    public init(backend: CursorBackend, store: SnapshotStore) {
        self.backend = backend
        self.store = store
    }

    /// names が nil なら全エントリ。現状がスナップショットと同じ名前には触らない。
    /// 1つ失敗しても残りの復元は続け、結果は名前ごとに返す。
    public func restore(names: [String]? = nil) throws -> RestoreReport {
        guard let manifest = try store.loadManifest() else {
            throw CursorKitError.snapshot("スナップショットが無い。`curstyle reset-system` で OS の標準へ戻せる(最終手段は再ログイン)")
        }
        var results: [NameResult] = []
        for name in (names ?? Array(manifest.entries.keys)).sorted() {
            guard let entry = manifest.entries[name] else {
                results.append(.init(name: name, outcome: .failed, readbackMatches: false, detail: "スナップショットにこの名前が無い"))
                continue
            }
            do {
                let before = try backend.read(name)
                if before.hash == entry.hash {
                    results.append(.init(name: name, outcome: .unchanged, readbackMatches: true))
                    continue
                }
                if let rep = try store.loadRep(entry) {
                    try backend.register(name, rep)
                    let after = try backend.read(name)
                    results.append(
                        .init(
                            name: name, outcome: .restored, readbackMatches: after.hash == entry.hash,
                            detail: after.hash == entry.hash ? nil : "読み戻し \(after.hash) ≠ スナップショット \(entry.hash)"))
                } else if let id = CursorCatalog.coreCursorID(of: name) {
                    // 削除だけだと、そのカーソルをすでに使ったアプリは名前で設定し続けて矢印になる(指差しで実測)。
                    // 削除してから HIServices に標準画像で登録し直させる。スナップショット(未登録)とは一致しなくなる。
                    try backend.remove(name)
                    try backend.registerSystemDefault(coreCursorID: id)
                    let registered = try backend.read(name).rep != nil
                    results.append(
                        .init(
                            name: name, outcome: .restored, readbackMatches: registered,
                            detail: registered ? "HIServices の標準画像で登録し直した" : "CoreCursorSet 後も未登録のまま"))
                } else {
                    try backend.remove(name)
                    let after = try backend.read(name)
                    results.append(
                        .init(
                            name: name, outcome: .removed, readbackMatches: after.hash == entry.hash,
                            detail: after.hash == entry.hash ? nil : "読み戻し \(after.hash) ≠ スナップショット(未登録)"))
                }
            } catch {
                results.append(.init(name: name, outcome: .failed, readbackMatches: false, detail: "\(error)"))
            }
        }
        let report = RestoreReport(results: results)
        if report.succeeded, names == nil {
            try store.saveJournal(.clean)
        }
        return report
    }
}

public final class CursorEngine {
    let backend: CursorBackend
    let store: SnapshotStore

    public init(backend: CursorBackend, store: SnapshotStore) {
        self.backend = backend
        self.store = store
    }

    /// 現在の登録内容を「標準」として取り込み直す。ただし自分が適用した内容のままの名前は、
    /// 以前のスナップショットを残す。標準画像はログインや色変更で変わるので、
    /// 自分の適用内容と違う名前は「OS が登録し直した新しい標準」とみなす。
    /// 他のカーソルアプリが書き換えた状態は区別できない(既知の制約)。
    ///
    /// ポインター色のカスタマイズ中は拒否する。この状態ではテーマが表示されないうえ、色付きの画像を
    /// 標準として取り込んでしまい、色をリセットするとシステムが ArrowS / IBeamS / cursor.13 を上書きする(実測)。
    public func refreshSnapshot() throws {
        if CursorEnvironment.current().cursorIsCustomized == true {
            throw CursorKitError.busy(
                "ポインターの色がカスタマイズされているため実行しない(テーマは画面に表示されず、色付きの画像を標準として取り込んでしまう)。システム設定 > アクセシビリティ > ディスプレイ > ポインタ で色をリセットしてから実行すること"
            )
        }
        let journal = try store.loadJournal()
        let existing = try store.loadManifest()
        let env = CursorEnvironment.current()
        var entries: [String: (result: ReadResult, capturedAt: Date, environment: CursorEnvironment)] = [:]
        var kept: [String: SnapshotEntry] = [:]
        for name in CursorCatalog.snapshotNames {
            let current = try backend.read(name)
            if let intended = journal.intended[name], intended == current.hash {
                guard let old = existing?.entries[name] else {
                    throw CursorKitError.snapshot(
                        "\(name) はテーマ適用中なのにスナップショットに標準画像が無い。`curstyle reset-system` で OS の標準へ戻せる(最終手段は再ログイン)")
                }
                kept[name] = old
                continue
            }
            entries[name] = (current, Date(), env)
        }
        // 残す名前は保存済み画像を読み直して、新しいスナップショットに書き戻す。
        for (name, old) in kept {
            let result: ReadResult = try store.loadRep(old).map { .registered($0) } ?? .unregistered
            entries[name] = (result, old.capturedAt, old.environment)
        }
        try store.save(entries: entries)
    }

    public func states() throws -> [(name: String, state: NameState, hash: String)] {
        let manifest = try store.loadManifest()
        let journal = try store.loadJournal()
        let loginTime = LoginSession.consoleLoginTime()
        return try CursorCatalog.snapshotNames.map { name in
            let hash = try backend.read(name).hash
            let state: NameState
            if let entry = manifest?.entries[name] {
                if hash == entry.hash {
                    state = .standard
                } else if journal.intended[name] == hash {
                    state = .themed
                } else if entry.registered == nil, CursorCatalog.coreCursorID(of: name) != nil {
                    // 未登録の cursor.N は、アプリが初めて使うときに HIServices が標準画像で登録する。
                    state = .standard
                } else if hash == "-", CursorCatalog.coreCursorID(of: name) != nil {
                    // 再ログイン・再起動・ポインターサイズ変更で OS が cursor.N を登録解除した状態(実測)。
                    // 標準の見た目に戻っており、同じく HIServices が使用時に登録し直す。
                    state = .unregistered
                } else if let loginTime, entry.capturedAt < loginTime {
                    // 再ログインで ArrowS / IBeamS の標準は別物に変わる(hotspot・size が違う。実測)。
                    // ログイン前に取ったスナップショットとの差は、他アプリの書き換えではなくこれとみなす。
                    state = .renewedAtLogin
                } else {
                    state = .unknown
                }
            } else {
                state = journal.intended[name] == hash ? .themed : .noSnapshot
            }
            return (name, state, hash)
        }
    }

    /// トランザクション適用: スナップショット更新 → ジャーナル記録 → 登録と読み戻し →
    /// 1つでも失敗したら、この適用で触った名前をスナップショットへ戻す。
    public func apply(_ theme: CursorTheme) throws -> ApplyReport {
        let env = CursorEnvironment.current()
        let plan = try theme.resolvedPlan()
        let previous = try store.loadJournal()
        try refreshSnapshot()

        // 前回のテーマが残っている名前のうち、今回のテーマに含まれないものは標準へ戻す。
        let planNames = Set(plan.map(\.name))
        let leftovers = previous.intended.keys.filter { !planNames.contains($0) }

        try store.saveActiveTheme(theme)

        var journal = Journal(
            status: .applying, themeName: theme.name,
            intended: previous.intended.merging(
                Dictionary(uniqueKeysWithValues: plan.map { ($0.name, $0.rep.contentHash) })
            ) { $1 },
            updatedAt: Date())
        try store.saveJournal(journal)

        var results: [NameResult] = []
        var touched: [String] = []
        let recovery = Recovery(backend: backend, store: store)
        // 前のテーマと今回の途中までが混ざった状態を残さないよう、ジャーナルにある全名前を標準へ戻す。
        func rollback(_ reason: String) throws -> ApplyReport {
            let report = try recovery.restore(names: Array(Set(journal.intended.keys).union(touched)))
            if report.succeeded {
                journal = .clean
            }
            try store.saveJournal(journal)
            return ApplyReport(
                themeName: theme.name, environment: env, results: results, failure: reason,
                rollback: report)
        }

        for item in plan {
            touched.append(item.name)
            do {
                try backend.register(item.name, item.rep)
                let readback = try backend.read(item.name)
                let expected = item.rep.contentHash
                guard readback.hash == expected else {
                    results.append(
                        .init(
                            name: item.name, outcome: .failed, readbackMatches: false,
                            detail: "読み戻し \(readback.hash) ≠ 登録 \(expected)"))
                    return try rollback("\(item.name) の読み戻しが登録内容と一致しない")
                }
                results.append(.init(name: item.name, outcome: .applied, readbackMatches: true))
            } catch {
                results.append(.init(name: item.name, outcome: .failed, readbackMatches: false, detail: "\(error)"))
                return try rollback("\(item.name): \(error)")
            }
        }

        if !leftovers.isEmpty {
            let report = try recovery.restore(names: Array(leftovers))
            results += report.results
            for r in report.results where r.outcome != .failed && r.readbackMatches { journal.intended[r.name] = nil }
        }
        journal.status = .applied
        try store.saveJournal(journal)
        return ApplyReport(
            themeName: theme.name, environment: env, results: results, failure: nil, rollback: nil)
    }
}
