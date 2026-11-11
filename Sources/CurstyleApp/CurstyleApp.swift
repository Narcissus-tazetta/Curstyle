import AppKit
import CursorKit
import SwiftUI

@main
struct CurstyleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        do {
            _model = State(initialValue: try AppModel())
        } catch {
            // 置き場所を作れないときは何もできないので、理由を見せて終わる。
            let alert = NSAlert()
            alert.messageText = "Curstyle を起動できません"
            alert.informativeText = "\(error)"
            alert.runModal()
            exit(1)
        }
    }

    var body: some Scene {
        Window("Curstyle", id: "main") {
            RootView(model: model)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    delegate.openFolder = { model.importSource = $0 }
                }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(after: .newItem) {
                Button("テーマを取り込む…") { chooseImportFolder(model: model) }
                    .keyboardShortcut("o")
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.statusSummary)
        Divider()
        if model.entries.isEmpty {
            Text("テーマがありません")
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
        Button("標準に戻す") { Task { await model.restore() } }
            .disabled(model.journal.status == .clean || model.busyMessage != nil)
        Divider()
        Button("Curstyle を開く…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button("終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
