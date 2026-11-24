import Foundation

/// 常駐ヘルパーの永続状態。ヘルパーが再起動しても回数上限と停止が効くようにディスクに置く。
public struct HelperState: Codable, Sendable {
    /// 入れ直したすべての時刻(全体の上限用)。
    public var reappliedAt: [Date] = []
    /// 原因の分からない消失(ポインター設定の変更以外で見つかった消失)で入れ直した時刻(競り合いの検知用)。
    public var unexplainedAt: [Date] = []
    public var stoppedAt: Date?
    public var stoppedReason: String?
    public var lastCheckAt: Date?
    public var lastResult: String?
    public var overlay: OverlayStatus?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reappliedAt = try c.decodeIfPresent([Date].self, forKey: .reappliedAt) ?? []
        unexplainedAt = try c.decodeIfPresent([Date].self, forKey: .unexplainedAt) ?? []
        stoppedAt = try c.decodeIfPresent(Date.self, forKey: .stoppedAt)
        stoppedReason = try c.decodeIfPresent(String.self, forKey: .stoppedReason)
        lastCheckAt = try c.decodeIfPresent(Date.self, forKey: .lastCheckAt)
        lastResult = try c.decodeIfPresent(String.self, forKey: .lastResult)
        overlay = try c.decodeIfPresent(OverlayStatus.self, forKey: .overlay)
    }
}

/// ヘルパー内の overlay 描画の状態。diagnose と apply / restore の確認に使う。
public struct OverlayStatus: Codable, Sendable {
    public var running = false
    public var themeName: String?
    public var startedAt: Date?
    public var stoppedAt: Date?
    /// ヘルパーの起動で overlay を始めた時刻(クラッシュの繰り返しの検知用)
    public var launchStarts: [Date] = []
    public var stoppedReason: String?
    public var yieldCount = 0
    public var yieldScenes: [String: Int] = [:]
    public var lastYieldAt: Date?
    public var unknownShapes = 0
    public var matcherEntries = 0

    public init() {}
}

extension SnapshotStore {
    var helperStateURL: URL { root.appendingPathComponent("helper.json") }

    public func loadHelperState() throws -> HelperState {
        guard FileManager.default.fileExists(atPath: helperStateURL.path) else { return HelperState() }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(HelperState.self, from: Data(contentsOf: helperStateURL))
    }

    public func saveHelperState(_ state: HelperState) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        try e.encode(state).write(to: helperStateURL, options: .atomic)
    }
}

/// イベントを受けてテーマが消えていれば入れ直す。判断はすべてジャーナル・読み戻し・永続状態から行い、
/// イベントの種類で区別するのは、回数上限に数えるかどうか(knownCause)だけ。
/// main キューから使う前提。
@MainActor
public final class AutoReapply {
    public struct Config: Sendable {
        public var debounce: TimeInterval = 2
        /// ポインターのサイズ・色の変更で OS がテーマを消すのは仕様どおりなので、その再適用は数えない。
        /// それ以外で見つかった消失(OS や他アプリとの競り合い)だけを window 内 maxUnexplained 回で止める。
        public var window: TimeInterval = 600
        public var maxUnexplained = 3
        /// 設定ファイルの書き換えが続くなど、原因が分かっている消失でも際限なく入れ直さないための上限。
        public var hardWindow: TimeInterval = 3600
        public var maxReapplies = 20
        /// 入れ直した後に OS が上書きしていないかを確かめる遅延(ログイン直後の競り合い対策)。
        public var verifyDelays: [TimeInterval] = [5, 30]
        public var busyRetryDelay: TimeInterval = 5

        public init() {}
    }

    let store: SnapshotStore
    let config: Config
    let makeBackend: () throws -> CursorBackend
    let notify: (String) -> Void
    let log: (String) -> Void
    private var pending: DispatchWorkItem?
    private var pendingReasons: [String] = []
    private var pendingKnownCause = false
    /// 同じ理由の通知を繰り返し出さないため。状態が変わったら出し直す。
    private var lastNotified: String?

    public init(
        store: SnapshotStore, config: Config = Config(), makeBackend: @escaping () throws -> CursorBackend,
        notify: @escaping (String) -> Void, log: @escaping (String) -> Void
    ) {
        self.store = store
        self.config = config
        self.makeBackend = makeBackend
        self.notify = notify
        self.log = log
    }

    /// knownCause: テーマが消える原因が分かっているイベント(ポインターのサイズ・色の変更)。
    public func trigger(_ reason: String, knownCause: Bool = false, after delay: TimeInterval? = nil) {
        if let delay, delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.trigger(reason, knownCause: knownCause)
            }
            return
        }
        pendingReasons.append(reason)
        pendingKnownCause = pendingKnownCause || knownCause
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let reasons = self.pendingReasons
            let knownCause = self.pendingKnownCause
            self.pendingReasons = []
            self.pendingKnownCause = false
            self.evaluate(reasons: reasons, knownCause: knownCause)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + config.debounce, execute: item)
    }

    private func notifyOnce(_ message: String) {
        guard lastNotified != message else { return }
        lastNotified = message
        notify(message)
    }

    func evaluate(reasons: [String], knownCause: Bool) {
        let label = Array(Set(reasons)).sorted().joined(separator: ",")
        var state: HelperState
        do {
            state = try store.loadHelperState()
        } catch {
            log(L10n.text("[{0}] helper.json を読めない: {1}", String(describing: label), String(describing: error)))
            notifyOnce(L10n.text("自動再適用の状態ファイルを読めないため停止中: {0}", String(describing: error)))
            return
        }
        let result = check(label: label, knownCause: knownCause, state: &state)
        state.lastCheckAt = Date()
        state.lastResult = result
        log("[\(label)] \(result)")
        do {
            try store.saveHelperState(state)
        } catch {
            log(L10n.text("helper.json を書けない: {0}", String(describing: error)))
        }
    }

    /// 結果の要約を返す。state は呼び出し側で保存する。
    private func check(label: String, knownCause: Bool, state: inout HelperState) -> String {
        let journal: Journal
        do {
            journal = try store.loadJournal()
        } catch {
            notifyOnce(L10n.text("ジャーナルを読めないため再適用しない: {0}", String(describing: error)))
            return L10n.text("ジャーナルを読めない: {0}", String(describing: error))
        }
        // 停止後に利用者が apply / restore したら、その判断を優先して再開する。
        if let stoppedAt = state.stoppedAt {
            guard journal.updatedAt > stoppedAt else {
                return L10n.text(
                    "停止中({0})。`curstyle helper resume` か apply / restore で再開する",
                    String(describing: state.stoppedReason ?? "-"))
            }
            state.stoppedAt = nil
            state.stoppedReason = nil
            state.reappliedAt = []
            state.unexplainedAt = []
        }
        switch journal.status {
        case .clean:
            lastNotified = nil
            return L10n.text("テーマ未適用(何もしない)")
        case .applying:
            notifyOnce(L10n.text("前回の適用が途中で止まっている。`curstyle restore` で標準へ戻してから適用し直すこと"))
            return L10n.text("ジャーナルが applying のまま(何もしない)")
        case .applied:
            break
        }
        if journal.backend == .overlay {
            lastNotified = nil
            return L10n.text("overlay 方式で適用中(入れ直しは不要。描画の状態は diagnose の overlay を参照)")
        }

        let backend: CursorBackend
        let lost: [String]
        do {
            backend = try makeBackend()
            lost = try journal.intended.keys.sorted().filter { name in
                try backend.read(name).hash != journal.intended[name]
            }
        } catch {
            notifyOnce(L10n.text("カーソルの状態を読めない: {0}", String(describing: error)))
            return L10n.text("状態を読めない: {0}", String(describing: error))
        }
        guard !lost.isEmpty else {
            lastNotified = nil
            return L10n.text("テーマは {0} 件とも適用中", String(describing: journal.intended.count))
        }

        if CursorEnvironment.current().cursorIsCustomized == true {
            notifyOnce(
                L10n.text("ポインターの色がカスタマイズされているため、消えたテーマ({0} 件)を入れ直さない。色をリセットすると自動で入れ直す", String(describing: lost.count))
            )
            return L10n.text("{0} 件が消えているが、ポインター色カスタマイズ中なので入れ直さない", String(describing: lost.count))
        }

        let now = Date()
        state.reappliedAt = state.reappliedAt.filter { now.timeIntervalSince($0) < config.hardWindow }
        state.unexplainedAt = state.unexplainedAt.filter { now.timeIntervalSince($0) < config.window }
        let lostSummary = L10n.text(
            "直近の消失 {0} 件: {1}…", String(describing: lost.count),
            String(describing: lost.prefix(5).joined(separator: ", ")))
        var limitReason: String?
        if !knownCause, state.unexplainedAt.count >= config.maxUnexplained {
            limitReason =
                L10n.text(
                    "{0} 分に {1} 回入れ直しても、原因の分からないままテーマが消える({2})", String(describing: Int(config.window / 60)),
                    String(describing: config.maxUnexplained), String(describing: lostSummary))
        } else if state.reappliedAt.count >= config.maxReapplies {
            limitReason = L10n.text(
                "{0} 分に {1} 回入れ直した({2})", String(describing: Int(config.hardWindow / 60)),
                String(describing: config.maxReapplies), String(describing: lostSummary))
        }
        if let reason = limitReason {
            state.stoppedAt = Date()
            state.stoppedReason = reason
            notifyOnce(L10n.text("自動再適用を停止した: {0}。`curstyle diagnose` で確認すること", String(describing: reason)))
            return L10n.text("停止: {0}", String(describing: reason))
        }

        let theme: CursorTheme
        do {
            guard let t = try store.loadActiveTheme() else {
                state.stoppedAt = Date()
                state.stoppedReason = L10n.text("適用中のテーマの写し(active-theme)が無い")
                notifyOnce(L10n.text("適用中のテーマの写しが無いため自動再適用を停止した。`curstyle apply <テーマ>` で適用し直すこと"))
                return L10n.text("停止: active-theme が無い")
            }
            theme = t
            // 写しがジャーナルの適用内容と食い違うなら、別のテーマを入れてしまうので止める。
            let mismatched = try theme.resolvedPlan().filter { journal.intended[$0.name] != $0.rep.contentHash }
            guard mismatched.isEmpty else {
                state.stoppedAt = Date()
                state.stoppedReason = L10n.text(
                    "active-theme がジャーナルと一致しない({0} 件)", String(describing: mismatched.count))
                notifyOnce(L10n.text("適用中のテーマの写しが記録と食い違うため自動再適用を停止した。`curstyle apply <テーマ>` で適用し直すこと"))
                return L10n.text(
                    "停止: active-theme とジャーナルが {0} 件食い違う(例 {1})", String(describing: mismatched.count),
                    String(describing: mismatched[0].name))
            }
        } catch {
            state.stoppedAt = Date()
            state.stoppedReason = L10n.text("active-theme を読めない: {0}", String(describing: error))
            notifyOnce(L10n.text("適用中のテーマの写しを読めないため自動再適用を停止した: {0}", String(describing: error)))
            return L10n.text("停止: active-theme を読めない: {0}", String(describing: error))
        }

        let report: ApplyReport
        do {
            // 上のジャーナルは、ロックを取る前に読んだもの。その間に利用者が restore / apply していたら、
            // 古い判断で入れ直して操作を取り消さないよう、ロックの中で読み直して食い違えば何もしない。
            let applied = try store.withLock { () -> ApplyReport? in
                guard try store.loadJournal().changeToken == journal.changeToken else { return nil }
                return try CursorEngine(backend: backend, store: store).apply(theme)
            }
            guard let applied else {
                trigger("journal-changed")
                return L10n.text("ロック取得前にジャーナルが変わったので入れ直さない。状態を確かめ直す")
            }
            report = applied
        } catch CursorKitError.busy(let message) {
            trigger("busy-retry", after: config.busyRetryDelay)
            return L10n.text(
                "{0} 件が消えているが、実行できない({1})。{2} 秒後に再試行", String(describing: lost.count), String(describing: message),
                String(describing: Int(config.busyRetryDelay)))
        } catch {
            state.reappliedAt.append(now)
            if !knownCause { state.unexplainedAt.append(now) }
            notifyOnce(L10n.text("テーマの自動再適用に失敗した: {0}", String(describing: error)))
            return L10n.text("再適用でエラー: {0}", String(describing: error))
        }
        state.reappliedAt.append(now)
        if !knownCause { state.unexplainedAt.append(now) }
        if let failure = report.failure {
            let rolledBack = report.rollback?.succeeded == true
            state.stoppedAt = Date()
            state.stoppedReason = L10n.text("再適用が失敗: {0}", String(describing: failure))
            notifyOnce(
                L10n.text(
                    "テーマの自動再適用に失敗し、{0}",
                    String(
                        describing: rolledBack
                            ? L10n.text("標準へ戻した") : L10n.text("標準へ戻すのにも失敗した。`curstyle restore` を実行すること"))))
            return L10n.text(
                "停止: 再適用が失敗({0})、ロールバック {1}", String(describing: failure),
                String(describing: rolledBack ? L10n.text("成功") : L10n.text("失敗")))
        }
        lastNotified = nil
        for delay in config.verifyDelays { trigger("verify+\(Int(delay))s", after: delay) }
        return
            L10n.text(
                "{0} 件が消えていたので入れ直した({1}…)。適用 {2} 件、読み戻し一致", String(describing: lost.count),
                String(describing: lost.prefix(5).joined(separator: ", ")), String(describing: report.results.count))
    }

    /// 利用者の明示的な再開。回数の記録も消す。
    nonisolated public static func resume(store: SnapshotStore) throws {
        var state = try store.loadHelperState()
        state.stoppedAt = nil
        state.stoppedReason = nil
        state.reappliedAt = []
        state.unexplainedAt = []
        try store.saveHelperState(state)
    }
}
