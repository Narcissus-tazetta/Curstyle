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
        if CursorEnvironment.current().cursorIsCustomized == true {
            throw CursorKitError.busy(
                "ポインターの色がカスタマイズされているため実行しない(overlay でも、色付きの画像を形として照合できるかは未確認)。システム設定 > アクセシビリティ > ディスプレイ > ポインタ で色をリセットしてから実行すること"
            )
        }
        _ = try OverlaySymbols()
        _ = try theme.resolvedPlan()
        var notes: [String] = []
        let previous = try store.loadJournal()
        if previous.backend == .cgs, !previous.intended.isEmpty {
            let report = try Recovery(backend: try CGSBackend(), store: store).restore(
                names: Array(previous.intended.keys))
            guard report.succeeded else {
                throw CursorKitError.snapshot("CGSBackend のテーマを標準へ戻せない。`curstyle restore` の結果を確認すること")
            }
            notes.append("CGSBackend のテーマ \(previous.intended.count) 件を標準へ戻した")
        }
        // 照合表の元になる標準画像を取り直す。CGS が使えない OS では、手元のスナップショットか AppKit の画像で照合する。
        do {
            try CursorEngine(backend: try CGSBackend(), store: store).refreshSnapshot()
        } catch {
            notes.append("スナップショットを取り直せない(\(error))。\(store.hasSnapshot ? "手元のスナップショット" : "AppKit の標準画像だけ")で形を照合する")
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
    private var runningJournalAt: Date?
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
        log("[overlay] 一時停止: \(reason)")
        if renderer != nil { stop(reason: "一時停止(\(reason))") }
    }

    public func resume(_ reason: String) {
        guard suspendedReasons.remove(reason) != nil else { return }
        log("[overlay] 一時停止の解除: \(reason)")
        sync(reason: "resume-\(reason)")
    }

    /// launch: ヘルパーの起動直後の呼び出し(クラッシュの繰り返しの検知に数える)。
    public func sync(reason: String, launch: Bool = false) {
        let journal: Journal
        do {
            journal = try store.loadJournal()
        } catch {
            log("[overlay \(reason)] ジャーナルを読めない: \(error)")
            stop(reason: "ジャーナルを読めない")
            return
        }
        guard journal.status == .applied, journal.backend == .overlay else {
            if renderer != nil { stop(reason: "ジャーナルが overlay の適用中でなくなった(\(reason))") }
            lastNotified = nil
            return
        }
        guard suspendedReasons.isEmpty else {
            if renderer != nil { stop(reason: "一時停止中") }
            return
        }
        if CursorEnvironment.current().cursorIsCustomized == true {
            if renderer != nil { stop(reason: "ポインター色がカスタマイズされた") }
            notifyOnce("ポインターの色がカスタマイズされているため overlay を止めた。色をリセットすると自動で再開する")
            return
        }
        if renderer != nil, runningJournalAt == journal.updatedAt { return }
        if renderer != nil { stop(reason: "テーマが変わった") }

        var state = (try? store.loadHelperState()) ?? HelperState()
        var status = state.overlay ?? OverlayStatus()
        if let stoppedReason = status.stoppedReason, let stoppedAt = status.stoppedAt, journal.updatedAt <= stoppedAt {
            log("[overlay \(reason)] 停止中(\(stoppedReason))。apply し直すと再開する")
            return
        }
        status.stoppedReason = nil
        if launch {
            let now = Date()
            status.launchStarts = status.launchStarts.filter { now.timeIntervalSince($0) < config.crashWindow } + [now]
            if status.launchStarts.count > config.maxLaunchStarts {
                status.stoppedReason =
                    "\(Int(config.crashWindow / 60)) 分に \(status.launchStarts.count) 回ヘルパーが起動し直した(overlay が落ち続けている可能性)"
                status.stoppedAt = now
                status.running = false
                state.overlay = status
                try? store.saveHelperState(state)
                notifyOnce("overlay を止めた: \(status.stoppedReason!)。`curstyle diagnose` で確認し、`curstyle restore` で標準へ戻せる")
                log("[overlay \(reason)] 停止: \(status.stoppedReason!)")
                return
            }
        }

        do {
            guard let theme = try store.loadActiveTheme() else {
                throw CursorKitError.theme("適用中のテーマの写し(active-theme)が無い")
            }
            let plan = Dictionary(uniqueKeysWithValues: try theme.resolvedPlan().map { ($0.name, $0.rep) })
            let symbols = try OverlaySymbols()
            let matcher = buildMatcher()
            let r = OverlayRenderer(symbols: symbols, matcher: matcher, plan: plan) { [log] in log("[overlay] \($0)") }
            r.onStatusChange = { [weak self] in self?.scheduleSave() }
            r.start()
            renderer = r
            runningJournalAt = journal.updatedAt
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
            log("[overlay \(reason)] テーマ \(theme.name) で開始(照合表 \(matcher.count) 件)")
        } catch {
            renderer?.stop()
            renderer = nil
            status.running = false
            status.stoppedReason = "開始できない: \(error)"
            status.stoppedAt = Date()
            state.overlay = status
            try? store.saveHelperState(state)
            notifyOnce("overlay を開始できない: \(error)")
            log("[overlay \(reason)] 開始できない: \(error)")
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
        runningJournalAt = nil
        let visible = r.stop()
        var state = (try? store.loadHelperState()) ?? HelperState()
        var status = state.overlay ?? OverlayStatus()
        status.running = false
        status.stoppedAt = Date()
        state.overlay = status
        try? store.saveHelperState(state)
        log("[overlay] 停止(\(reason))")
        if !visible { fatal("overlay を止めても本物のカーソルが表示に戻らない。プロセスを終了して WindowServer に戻させる") }
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
            log("helper.json を書けない: \(error)")
        }
    }

    /// 照合元は、CGS で読んだ現在の標準 → スナップショット → AppKit のファクトリの順。
    /// 先に入れたものが優先される。
    private func buildMatcher() -> ShapeMatcher {
        let matcher = ShapeMatcher()
        do {
            let backend = try CGSBackend()
            for name in CursorCatalog.snapshotNames {
                if let rep = try backend.read(name).rep { matcher.add(name: name, rep: rep) }
            }
        } catch {
            log("[overlay] CGS で標準画像を読めない(\(error))。スナップショットと AppKit で照合する")
        }
        do {
            if let manifest = try store.loadManifest() {
                for (name, entry) in manifest.entries {
                    if let rep = try store.loadRep(entry) { matcher.add(name: name, rep: rep) }
                }
            }
        } catch {
            log("[overlay] スナップショットを読めない: \(error)")
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
