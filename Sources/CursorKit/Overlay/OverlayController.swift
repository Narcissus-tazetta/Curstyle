import AppKit

/// CLI 側: overlay 方式での適用と停止。描画そのものは常駐ヘルパー(OverlayController)が行う。
public enum OverlayActivation {
    /// CLI → ヘルパーへの「ジャーナルが変わった」の合図。同じユーザーのプロセス間でだけ届く。
    public static let changedNotification = Notification.Name("io.github.narcissus-tazetta.curstyle.changed")

    public static func postChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// テーマを検証して active-theme に写し、ジャーナルを overlay で applied にする。登録はしない。
    /// CGSBackend のテーマが残っていれば先に標準へ戻す(NSCursor.currentSystem が標準画像を返すようにするため)。
    /// 戻り値は利用者に見せる補足。
    public static func apply(_ theme: CursorTheme, store: SnapshotStore) throws -> [String] {
        let previous = try store.loadJournal()
        try previous.requireCompletedApplication()
        if CursorEnvironment.current().cursorIsCustomized == true {
            throw CursorKitError.busy(
                L10n.text(
                    "ポインターの色がカスタマイズされているため実行しない(overlay でも、色付きの画像を形として照合できるかは未確認)。システム設定 > アクセシビリティ > ディスプレイ > ポインタ で色をリセットしてから実行すること"
                )
            )
        }
        _ = try OverlaySymbols()
        _ = try theme.visiblePlan()
        var notes: [String] = []
        if previous.backend == .cgs, !previous.intended.isEmpty {
            let report = try Recovery(backend: try CGSBackend(), store: store).restore(
                names: Array(previous.intended.keys))
            guard report.succeeded else {
                throw CursorKitError.snapshot(L10n.text("CGSBackend のテーマを標準へ戻せない。`curstyle restore` の結果を確認すること"))
            }
            notes.append(L10n.text("CGSBackend のテーマ {0} 件を標準へ戻した", String(describing: previous.intended.count)))
        }
        // 照合表の元になる標準画像を取り直す。CGS が使えない OS では、手元のスナップショットか AppKit の画像で照合する。
        do {
            try CursorEngine(backend: try CGSBackend(), store: store).refreshSnapshot()
        } catch {
            notes.append(
                L10n.text(
                    "スナップショットを取り直せない({0})。{1}で形を照合する", String(describing: error),
                    String(describing: store.hasSnapshot ? L10n.text("手元のスナップショット") : L10n.text("AppKit の標準画像だけ"))))
        }
        try store.saveActiveTheme(theme)
        try store.saveJournal(
            Journal(status: .applied, themeName: theme.name, intended: [:], updatedAt: Date(), backend: .overlay))
        postChanged()
        return notes
    }
}

/// ヘルパー側: ジャーナルに合わせて overlay の描画を始める・止める。main キューから使う前提。
@MainActor
public final class OverlayController {
    public struct Config: Sendable {
        /// ヘルパーの起動で overlay を始めた回数がこの時間内に上限を超えたら、クラッシュの繰り返しとみなして止める。
        public var crashWindow: TimeInterval = 600
        public var maxLaunchStarts = 3
        public init() {}
    }

    let store: SnapshotStore
    let config: Config
    let log: (String) -> Void
    let notify: (String) -> Void
    /// 本物を表示に戻せなかったとき。プロセスを終了すれば WindowServer が戻す。
    let fatal: (String) -> Never
    private var renderer: OverlayRenderer?
    private var runningJournalToken: String?
    private var saveItem: DispatchWorkItem?
    private var lastNotified: String?

    public init(
        store: SnapshotStore, config: Config = Config(), log: @escaping (String) -> Void,
        notify: @escaping (String) -> Void, fatal: @escaping (String) -> Never
    ) {
        self.store = store
        self.config = config
        self.log = log
        self.notify = notify
        self.fatal = fatal
    }

    public var isRunning: Bool { renderer != nil }
    /// 画面ロック・スクリーンセーバー・ユーザー切替の間は本物に任せる。ロック画面の上には自前が出ず、
    /// 本物を隠したままだとカーソルが消える(実機で確認)。
    private var suspendedReasons: Set<String> = []

    public func suspend(_ reason: String) {
        guard suspendedReasons.insert(reason).inserted else { return }
        log(L10n.text("[overlay] 一時停止: {0}", String(describing: reason)))
        if renderer != nil { stop(reason: L10n.text("一時停止({0})", String(describing: reason))) }
    }

    public func resume(_ reason: String) {
        guard suspendedReasons.remove(reason) != nil else { return }
        log(L10n.text("[overlay] 一時停止の解除: {0}", String(describing: reason)))
        sync(reason: "resume-\(reason)")
    }

    /// launch: ヘルパーの起動直後の呼び出し(クラッシュの繰り返しの検知に数える)。
    public func sync(reason: String, launch: Bool = false) {
        let journal: Journal
        do {
            journal = try store.loadJournal()
        } catch {
            log(L10n.text("[overlay {0}] ジャーナルを読めない: {1}", String(describing: reason), String(describing: error)))
            stop(reason: L10n.text("ジャーナルを読めない"))
            return
        }
        guard journal.status == .applied, journal.backend == .overlay else {
            if renderer != nil { stop(reason: L10n.text("ジャーナルが overlay の適用中でなくなった({0})", String(describing: reason))) }
            lastNotified = nil
            return
        }
        guard suspendedReasons.isEmpty else {
            if renderer != nil { stop(reason: L10n.text("一時停止中")) }
            return
        }
        if CursorEnvironment.current().cursorIsCustomized == true {
            if renderer != nil { stop(reason: L10n.text("ポインター色がカスタマイズされた")) }
            notifyOnce(L10n.text("ポインターの色がカスタマイズされているため overlay を止めた。色をリセットすると自動で再開する"))
            return
        }
        if renderer != nil, runningJournalToken == journal.changeToken { return }
        if renderer != nil { stop(reason: L10n.text("テーマが変わった")) }

        var state = (try? store.loadHelperState()) ?? HelperState()
        var status = state.overlay ?? OverlayStatus()
        if let stoppedReason = status.stoppedReason, let stoppedAt = status.stoppedAt, journal.updatedAt <= stoppedAt {
            log(
                L10n.text(
                    "[overlay {0}] 停止中({1})。apply し直すと再開する", String(describing: reason),
                    String(describing: stoppedReason)))
            return
        }
        status.stoppedReason = nil
        if launch {
            let now = Date()
            status.launchStarts = status.launchStarts.filter { now.timeIntervalSince($0) < config.crashWindow } + [now]
            if status.launchStarts.count > config.maxLaunchStarts {
                status.stoppedReason =
                    L10n.text(
                        "{0} 分に {1} 回ヘルパーが起動し直した(overlay が落ち続けている可能性)",
                        String(describing: Int(config.crashWindow / 60)), String(describing: status.launchStarts.count))
                status.stoppedAt = now
                status.running = false
                state.overlay = status
                try? store.saveHelperState(state)
                notifyOnce(
                    L10n.text(
                        "overlay を止めた: {0}。`curstyle diagnose` で確認し、`curstyle restore` で標準へ戻せる",
                        String(describing: status.stoppedReason!)))
                log(
                    L10n.text(
                        "[overlay {0}] 停止: {1}", String(describing: reason), String(describing: status.stoppedReason!)))
                return
            }
        }

        do {
            guard let theme = try store.loadActiveTheme() else {
                throw CursorKitError.theme(L10n.text("適用中のテーマの写し(active-theme)が無い"))
            }
            let plan = Dictionary(uniqueKeysWithValues: try theme.resolvedPlan().map { ($0.name, $0.rep) })
            let symbols = try OverlaySymbols()
            let matcher = buildMatcher()
            let r = OverlayRenderer(symbols: symbols, matcher: matcher, plan: plan, restoreFailed: fatal) { [log] in
                log("[overlay] \($0)")
            }
            r.onStatusChange = { [weak self] in self?.scheduleSave() }
            r.start()
            renderer = r
            runningJournalToken = journal.changeToken
            status.running = true
            status.themeName = theme.name
            status.startedAt = Date()
            status.stoppedAt = nil
            status.yieldCount = 0
            status.yieldScenes = [:]
            status.lastYieldAt = nil
            status.unknownShapes = 0
            status.matcherEntries = matcher.count
            state.overlay = status
            try store.saveHelperState(state)
            lastNotified = nil
            log(
                L10n.text(
                    "[overlay {0}] テーマ {1} で開始(照合表 {2} 件)", String(describing: reason), String(describing: theme.name),
                    String(describing: matcher.count)))
        } catch {
            // 本物を表示に戻せなかった場合に fatal へ回すため、直接 stop() せず stop(reason:) を通す。
            stop(reason: L10n.text("開始できない: {0}", String(describing: error)))
            status.running = false
            status.stoppedReason = L10n.text("開始できない: {0}", String(describing: error))
            status.stoppedAt = Date()
            state.overlay = status
            try? store.saveHelperState(state)
            notifyOnce(L10n.text("overlay を開始できない: {0}", String(describing: error)))
            log(L10n.text("[overlay {0}] 開始できない: {1}", String(describing: reason), String(describing: error)))
        }
    }

    public func displaysChanged() {
        renderer?.rebuildWindows()
    }

    public func pointerPrefsChanged() {
        renderer?.updateScale()
        sync(reason: "pointer-prefs")
    }

    private func stop(reason: String) {
        guard let r = renderer else { return }
        renderer = nil
        runningJournalToken = nil
        let visible = r.stop()
        var state = (try? store.loadHelperState()) ?? HelperState()
        var status = state.overlay ?? OverlayStatus()
        status.running = false
        status.stoppedAt = Date()
        state.overlay = status
        try? store.saveHelperState(state)
        log(L10n.text("[overlay] 停止({0})", String(describing: reason)))
        if !visible { fatal(L10n.text("overlay を止めても本物のカーソルが表示に戻らない。プロセスを終了して WindowServer に戻させる")) }
    }

    /// yield や未知の形は頻繁に起きうるので、まとめて書く。
    private func scheduleSave() {
        saveItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveStatus() }
        }
        saveItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    private func saveStatus() {
        guard let r = renderer else { return }
        var state = (try? store.loadHelperState()) ?? HelperState()
        var status = state.overlay ?? OverlayStatus()
        status.yieldCount = r.status.yieldCount
        status.yieldScenes = r.status.yieldScenes
        status.lastYieldAt = r.status.lastYieldAt
        status.unknownShapes = r.status.unknownShapes.count
        state.overlay = status
        do {
            try store.saveHelperState(state)
        } catch {
            log(L10n.text("helper.json を書けない: {0}", String(describing: error)))
        }
    }

    private func buildMatcher() -> ShapeMatcher {
        let matcher = ShapeMatcher()
        do {
            let backend = try CGSBackend()
            for name in CursorCatalog.snapshotNames {
                if let rep = try backend.read(name).rep { matcher.add(name: name, rep: rep) }
            }
        } catch {
            log(L10n.text("[overlay] CGS で標準画像を読めない({0})。スナップショットと AppKit で照合する", String(describing: error)))
        }
        do {
            if let manifest = try store.loadManifest() {
                for (name, entry) in manifest.entries {
                    if let rep = try store.loadRep(entry) { matcher.add(name: name, rep: rep) }
                }
            }
        } catch {
            log(L10n.text("[overlay] スナップショットを読めない: {0}", String(describing: error)))
        }
        matcher.addAppKitFactories()
        return matcher
    }

    private func notifyOnce(_ message: String) {
        guard lastNotified != message else { return }
        lastNotified = message
        notify(message)
    }
}
