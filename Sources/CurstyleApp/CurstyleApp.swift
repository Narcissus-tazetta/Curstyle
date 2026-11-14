import AppKit
import CursorKit
import SwiftUI

@main
struct CurstyleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel
    @State private var updates = UpdateService()
    @AppStorage(L10n.preferenceKey, store: L10n.preferences) private var language = ""

    init() {
        do {
            _model = State(initialValue: try AppModel())
        } catch {
            // 置き場所を作れないときは何もできないので、理由を見せて終わる。
            let alert = NSAlert()
            alert.messageText = L10n.text("Curstyle を起動できません")
            alert.informativeText = "\(error)"
            alert.runModal()
            exit(1)
        }
    }

    var body: some Scene {
        Window("Curstyle", id: "main") {
            RootView(model: model)
                .environment(updates)
                .environment(\.locale, Locale(identifier: L10n.language))
                .id(language)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    delegate.openFolder = { model.importSource = $0 }
                    model.reload()
                    model.refreshStatus()
                }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L10n.text("テーマを取り込む…")) { chooseImportFolder(model: model) }
                    .keyboardShortcut("o")
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
                .environment(updates)
                .environment(\.locale, Locale(identifier: L10n.language))
                .id(language)
        } label: {
            Image(systemName: model.journal.status == .applied ? "cursorarrow.rays" : "cursorarrow")
                .accessibilityLabel("Curstyle")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Dock のアイコンへのドロップや `open -a Curstyle <フォルダ / .cape>` で渡されたものを取り込みシートに回す。
    /// 起動と同時に渡されるとウィンドウより先に届くので、受け手ができるまで取っておく。
    var openFolder: ((URL) -> Void)? {
        didSet {
            if let url = pendingFolder, let openFolder {
                pendingFolder = nil
                openFolder(url)
            }
        }
    }
    private var pendingFolder: URL?

    /// ウィンドウを閉じてもメニューバーに残る。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let openFolder {
            openFolder(url)
        } else {
            pendingFolder = url
        }
    }
}

struct MenuBarContent: View {
    let model: AppModel
    @Environment(UpdateService.self) private var updates
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.statusSummary)
        Divider()
        if model.entries.isEmpty {
            Text(L10n.text("テーマがありません"))
        }
        ForEach(model.entries) { entry in
            Toggle(
                entry.theme.name,
                isOn: Binding(
                    get: { model.isActive(entry) },
                    set: { on in
                        if on { Task { await model.apply(entry) } }
                    })
            )
            .disabled(model.busyMessage != nil)
        }
        Divider()
        Button(L10n.text("標準に戻す")) { Task { await model.restore() } }
            .disabled(model.journal.status == .clean || model.busyMessage != nil)
        Divider()
        Button(L10n.text("Curstyle を開く…")) {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button(L10n.text("アップデートを確認…")) { updates.checkForUpdates() }
            .disabled(!updates.isAvailable)
        Button(L10n.text("終了")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
