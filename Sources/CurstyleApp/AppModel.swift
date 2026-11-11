import AppKit
import CursorKit
import Observation
import SwiftUI

enum SidebarItem: Hashable {
    case theme(String)
    case settings
}

/// 操作の結果を画面上部のバナーで伝える。
struct Banner: Identifiable, Equatable {
    enum Kind { case success, failure, info }
    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String?
}

@MainActor
@Observable
final class AppModel {
    let store: SnapshotStore
    let library: ThemeLibrary

    var entries: [ThemeLibrary.Entry] = []
    var brokenThemes: [(directory: URL, message: String)] = []
    var selection: SidebarItem?
    var journal: Journal = .clean
    var activeTheme: CursorTheme?
    var helperState = HelperState()
    var helperService: HelperService.State = .unavailable
    var hasLegacyHelper = false
    var diagnostics: DiagnosticReport?
    var isDiagnosing = false
    /// 適用・復元の最中。二重に押されないよう、その間はボタンを止める。
    var busyMessage: String?
    var banner: Banner?
    var importSource: URL?
    var backdrop: PreviewBackdrop = .checker
    var showsHotspot = false

    init() throws {
        store = try SnapshotStore()
        library = try ThemeLibrary()
        reload()
        // CLI・ヘルパー・他のウィンドウからの適用と復元の合図。
        DistributedNotificationCenter.default().addObserver(
            forName: OverlayActivation.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
        if selection == nil {
            selection = entries.first.map { .theme($0.id) } ?? .settings
        }
    }

    // MARK: 状態

    func reload() {
        let loaded = library.load()
        entries = loaded.entries
        brokenThemes = loaded.errors
        if case .theme(let id)? = selection, !entries.contains(where: { $0.id == id }) {
            selection = entries.first.map { .theme($0.id) }
        }
        refreshStatus()
    }

    func refreshStatus() {
        do {
            journal = try store.loadJournal()
            activeTheme = journal.status == .applied ? try store.loadActiveTheme() : nil
        } catch {
            journal = .clean
            activeTheme = nil
            show(.failure, L10n.text("適用状態を読めません"), "\(error)")
        }
        helperState = (try? store.loadHelperState()) ?? HelperState()
        helperService = HelperService.state
        hasLegacyHelper = HelperService.hasLegacyInstall
    }

    var activeFingerprint: String? { activeTheme?.fingerprint }

    func isActive(_ entry: ThemeLibrary.Entry) -> Bool {
        entry.fingerprint == activeFingerprint
    }

    /// ライブラリに無いテーマ(CLI で適用したものなど)が適用されているとき、その名前。
    var activeOutsideLibrary: String? {
        guard let active = activeTheme, !entries.contains(where: { $0.fingerprint == active.fingerprint }) else {
            return nil
        }
        return active.name
    }

    var statusSummary: String {
        guard journal.status == .applied, let name = journal.themeName else {
            return journal.status == .applying ? L10n.text("適用が途中で止まっています") : L10n.text("標準のカーソル")
        }
        return journal.backend == .overlay ? L10n.text("{0}(overlay 方式)", String(describing: name)) : name
    }

    var warningCount: Int {
        diagnostics?.items.filter { $0.level != .ok }.count ?? 0
    }

    func entry(id: String) -> ThemeLibrary.Entry? {
        entries.first { $0.id == id }
    }

    func show(_ kind: Banner.Kind, _ title: String, _ detail: String? = nil) {
        banner = Banner(kind: kind, title: title, detail: detail)
    }

    // MARK: 適用・復元

    func apply(_ entry: ThemeLibrary.Entry) async {
        guard busyMessage == nil else { return }
        busyMessage = L10n.text("{0} を適用しています…", String(describing: entry.theme.name))
        defer { busyMessage = nil }
        // 「適用しています」を先に描かせる。登録そのものはメインスレッドで行う(CLI と同じ呼び方にそろえる)。
        await Task.yield()
        do {
            let report = try store.withLock {
                try CursorEngine(backend: try CGSBackend(), store: store).apply(entry.theme)
            }
            OverlayActivation.postChanged()
            if let failure = report.failure {
                let rolledBack = report.rollback?.succeeded == true
                show(
                    .failure, L10n.text("適用できませんでした"),
                    "\(failure)。\(rolledBack ? L10n.text("前の状態へ戻しました。") : L10n.text("前の状態へ戻せなかった名前があります。「標準に戻す」を試してください。"))"
                )
            } else {
                let count = report.results.filter { $0.outcome == .applied }.count
                lastAppliedEntryID = entry.id
                show(
                    .success, L10n.text("{0} を適用しました", String(describing: entry.theme.name)),
                    L10n.text("{0} 件の登録を読み戻して一致を確かめました。", String(describing: count)))
            }
        } catch {
            show(.failure, L10n.text("適用できませんでした"), "\(error)")
        }
        refreshStatus()
    }

    func restore() async {
        guard busyMessage == nil else { return }
        busyMessage = L10n.text("標準のカーソルに戻しています…")
        defer { busyMessage = nil }
        await Task.yield()
        do {
            if journal.backend == .overlay {
                try store.withLock { try store.saveJournal(.clean) }
                OverlayActivation.postChanged()
                show(.success, L10n.text("標準のカーソルに戻しました"), L10n.text("overlay 方式の描画を止めるよう、ヘルパーに伝えました。"))
            } else {
                let report = try store.withLock {
                    try Recovery(backend: try CGSBackend(), store: store).restore()
                }
                OverlayActivation.postChanged()
                if report.succeeded {
                    show(.success, L10n.text("標準のカーソルに戻しました"), L10n.text("すべての名前がスナップショットと一致しました。"))
                } else {
                    let failed = report.results.filter { $0.outcome == .failed || !$0.readbackMatches }.map(\.name)
                    show(.failure, L10n.text("一部を戻せませんでした"), failed.joined(separator: ", "))
                }
            }
        } catch {
            show(.failure, L10n.text("標準に戻せませんでした"), "\(error)")
        }
        refreshStatus()
    }

    // MARK: ライブラリ

    func add(_ theme: CursorTheme) {
        do {
            let entry = try library.add(theme)
            reload()
            selection = .theme(entry.id)
            show(.success, L10n.text("{0} を追加しました", String(describing: theme.name)))
        } catch {
            show(.failure, L10n.text("追加できませんでした"), "\(error)")
        }
    }

    /// 適用中のテーマを編集しても、カーソルは書き換えずライブラリにだけ保存する(「変更を適用」で反映)。
    @discardableResult
    func update(_ entry: ThemeLibrary.Entry, with theme: CursorTheme) -> Bool {
        do {
            try library.update(entry, with: theme)
            reload()
            show(
                .success, L10n.text("{0} を保存しました", String(describing: theme.name)),
                hasPendingChanges(self.entry(id: entry.id) ?? entry)
                    ? L10n.text("画面のカーソルはまだ前の内容です。「変更を適用」で反映します。") : nil)
            return true
        } catch {
            show(.failure, L10n.text("保存できませんでした"), "\(error)")
            return false
        }
    }

    /// アプリで最後に適用したライブラリのテーマ。編集で中身(指紋)が変わっても「適用中だったテーマ」を辿るため。
    private static let lastAppliedKey = "lastAppliedEntryID"
    var lastAppliedEntryID: String? {
        get { UserDefaults.standard.string(forKey: Self.lastAppliedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastAppliedKey) }
    }

    /// 適用中のテーマを編集して、画面のカーソルとライブラリの中身が食い違っている。
    /// テーマ名も比べるのは、アプリで適用した後に CLI などで別のテーマを適用した場合を除くため
    /// (名前を変えてから編集したテーマは、ここで食い違いを見落とす)。
    func hasPendingChanges(_ entry: ThemeLibrary.Entry) -> Bool {
        journal.status == .applied && lastAppliedEntryID == entry.id && journal.themeName == entry.theme.name
            && activeTheme != nil && !isActive(entry)
    }

    func rename(_ entry: ThemeLibrary.Entry, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.theme.name else { return }
        do {
            _ = try library.rename(entry, to: trimmed)
            reload()
        } catch {
            show(.failure, L10n.text("名前を変えられませんでした"), "\(error)")
        }
    }

    func remove(_ entry: ThemeLibrary.Entry) {
        do {
            try library.remove(entry)
            reload()
            show(
                .info, L10n.text("{0} をゴミ箱に入れました", String(describing: entry.theme.name)),
                isActive(entry) ? L10n.text("適用中のカーソルはそのまま残ります。") : nil)
        } catch {
            show(.failure, L10n.text("削除できませんでした"), "\(error)")
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: 診断

    func runDiagnostics() async {
        guard !isDiagnosing else { return }
        isDiagnosing = true
        defer { isDiagnosing = false }
        await Task.yield()
        diagnostics = Diagnostics.run(store: store)
        refreshStatus()
    }

    func exportReport() {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "curstyle-report-\(formatter.string(from: Date())).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Diagnostics.fullReport(store: store).write(to: url, atomically: true, encoding: .utf8)
            show(.success, L10n.text("診断レポートを書き出しました"), url.lastPathComponent)
        } catch {
            show(.failure, L10n.text("書き出せませんでした"), "\(error)")
        }
    }

    // MARK: ヘルパー

    func setHelperEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try HelperService.enable()
            } else {
                try HelperService.disable()
            }
        } catch {
            show(.failure, enabled ? L10n.text("ヘルパーを登録できませんでした") : L10n.text("ヘルパーを止められませんでした"), "\(error)")
        }
        refreshStatus()
    }

    func resumeHelper() {
        do {
            try AutoReapply.resume(store: store)
            show(.success, L10n.text("自動再適用を再開しました"), L10n.text("次のイベントか、ヘルパーの再起動で確かめます。"))
        } catch {
            show(.failure, L10n.text("再開できませんでした"), "\(error)")
        }
        refreshStatus()
    }
}
