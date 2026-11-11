import AppKit
import CursorKit
import Foundation

/// ログイン時に起動する常駐ヘルパー(LaunchAgent)。テーマが消えるきっかけになるイベントだけを拾い、
/// 判断は AutoReapply に任せる。ポーリングはしない。
enum Helper {
    static let label = "io.github.narcissus-tazetta.curstyle.helper"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var domain: String { "gui/\(getuid())" }

    // MARK: run

    @MainActor
    static func run(store: SnapshotStore) -> Never {
        let logger = HelperLog(url: store.root.appendingPathComponent("helper.log"))
        let reapply = AutoReapply(
            store: store, makeBackend: { try CGSBackend() },
            notify: { message in
                logger.write("通知: \(message)")
                postNotification(message, log: logger)
            },
            log: { logger.write($0) })
        logger.write("起動 pid=\(getpid())")
        let ws = NSWorkspace.shared.notificationCenter
        let overlay = OverlayController(
            store: store,
            log: { logger.write($0) },
            notify: { message in
                logger.write("通知: \(message)")
                postNotification(message, log: logger)
            },
            fatal: { message in
                logger.write(message)
                // launchd の KeepAlive(SuccessfulExit=false)で起動し直させる。
                exit(1)
            })
        // 画面ロック・スクリーンセーバーの通知名は公開 API ではないが、長く使われているもの(macOS 27.2 で受信を確認する)。
        let dnc = DistributedNotificationCenter.default()
        for (begin, end, reason) in [
            ("com.apple.screenIsLocked", "com.apple.screenIsUnlocked", "screen-lock"),
            ("com.apple.screensaver.didstart", "com.apple.screensaver.didstop", "screensaver"),
        ] {
            dnc.addObserver(forName: Notification.Name(begin), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { overlay.suspend(reason) }
            }
            dnc.addObserver(forName: Notification.Name(end), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { overlay.resume(reason) }
            }
        }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { overlay.suspend("session-inactive") }
        }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { overlay.resume("session-inactive") }
        }
        // apply / restore からの合図。ジャーナルを読み直して overlay を始める・止める。
        DistributedNotificationCenter.default().addObserver(
            forName: OverlayActivation.changedNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { overlay.sync(reason: "changed") }
        }

        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let reason = name.rawValue
            ws.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    reapply.trigger(reason)
                    overlay.sync(reason: reason)
                }
            }
        }
        let displayErr = DisplayWatcher.start {
            reapply.trigger("display")
            overlay.displaysChanged()
        }
        if displayErr != .success { logger.write("ディスプレイ変更の監視を登録できない: CGError=\(displayErr.rawValue)") }
        // ポインターのサイズ・色の変更は distributed notification で取れない(Phase 3 で実測)。
        // cfprefsd が書き出す plist の変更で拾う。書き出しは設定変更から最大8秒ほど遅れる。
        let prefsWatcher = PrefsWatcher { env, changed in
            logger.write(
                "universalaccess の設定ファイルが書き換わった\(changed ? "(ポインター設定が変化)" : "") size=\(env.cursorSize.map { "\($0)" } ?? "nil") customized=\(env.cursorIsCustomized.map { "\($0)" } ?? "nil")"
            )
            reapply.trigger("pointer-prefs", knownCause: true)
            overlay.pointerPrefsChanged()
        }
        prefsWatcher.start()

        // ログイン直後は OS がカーソルを登録し直している最中の可能性があるので、少し後にも確かめる。
        reapply.trigger("launch")
        overlay.sync(reason: "launch", launch: true)
        for delay: TimeInterval in [10, 40] { reapply.trigger("launch+\(Int(delay))s", after: delay) }

        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler {
            logger.write("SIGTERM で終了")
            exit(0)
        }
        term.resume()
        // RunLoop.main.run() だけだと CGDisplayRegisterReconfigurationCallback が呼ばれない(外部ディスプレイの抜き差しで実測)。
        // NSApplication を Dock に出さない設定で回す。
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        withExtendedLifetime((prefsWatcher, term, overlay)) { app.run() }
        exit(0)
    }

    /// LaunchAgent はバンドルを持たないので UNUserNotificationCenter は使えない。osascript の通知で代用する
    /// (送信元は「スクリプトエディタ」と表示される)。
    static func postNotification(_ message: String, log: HelperLog) {
        let escaped = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(escaped)\" with title \"Curstyle\""]
        p.terminationHandler = { proc in
            if proc.terminationStatus != 0 { log.write("osascript が失敗 status=\(proc.terminationStatus)") }
        }
        do {
            try p.run()
        } catch {
            log.write("osascript を起動できない: \(error)")
        }
    }

    // MARK: install / uninstall / status

    /// 実行ファイルを Application Support に写してから登録する。~/Desktop などの保護フォルダにある実行ファイルを
    /// launchd から起動すると、TCC の許可ダイアログ待ちで dyld が止まる(実測)。写した先のパスを返す。
    @discardableResult
    static func install(executable: URL) throws -> URL {
        let fm = FileManager.default
        let logDir = SnapshotStore.defaultRoot
        let binDir = logDir.appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        let resourceBundle = L10n.resourceBundleURL
        let resourceDestination = binDir.appendingPathComponent(resourceBundle.lastPathComponent)
        let resourceStaging = binDir.appendingPathComponent("resources.staging-\(UUID().uuidString)")
        try fm.copyItem(at: resourceBundle, to: resourceStaging)
        if fm.fileExists(atPath: resourceDestination.path) {
            _ = try fm.replaceItemAt(resourceDestination, withItemAt: resourceStaging)
        } else {
            try fm.moveItem(at: resourceStaging, to: resourceDestination)
        }
        let installed = binDir.appendingPathComponent("curstyle")
        let staging = binDir.appendingPathComponent("curstyle.staging-\(UUID().uuidString)")
        try fm.copyItem(at: executable, to: staging)
        // 動いているヘルパーの実行ファイルを上書きしないよう rename で置き換える。
        guard rename(staging.path, installed.path) == 0 else {
            let code = errno
            try? fm.removeItem(at: staging)
            throw CursorKitError.io("\(installed.path) へ置き換えられない errno=\(code)")
        }
        let executable = installed
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable.path, "helper", "run"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 30,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Background",
            "StandardErrorPath": logDir.appendingPathComponent("helper.stderr.log").path,
        ]
        try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        if fm.fileExists(atPath: plistURL.path) {
            _ = try launchctl(["bootout", "\(domain)/\(label)"], allowFailure: true)
        }
        try data.write(to: plistURL, options: .atomic)
        try launchctl(["bootstrap", domain, plistURL.path])
        return installed
    }

    static func uninstall() throws {
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try launchctl(["bootout", "\(domain)/\(label)"], allowFailure: true)
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    /// launchd に登録されているか、動いているなら pid。
    static func launchdState() -> String {
        guard let out = try? launchctl(["print", "\(domain)/\(label)"], allowFailure: true), out.status == 0 else {
            return FileManager.default.fileExists(atPath: plistURL.path)
                ? "plist はあるが launchd に未登録(次回ログインで読み込まれる)" : "未インストール"
        }
        let pid = out.output.split(separator: "\n").first { $0.contains("pid = ") }
        let state = out.output.split(separator: "\n").first {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("state = ")
        }
        return
            "登録済み \(state?.trimmingCharacters(in: .whitespaces) ?? "") \(pid?.trimmingCharacters(in: .whitespaces) ?? "")"
    }

    @discardableResult
    static func launchctl(_ arguments: [String], allowFailure: Bool = false) throws -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        if p.terminationStatus != 0, !allowFailure {
            throw CursorKitError.io(
                "launchctl \(arguments.joined(separator: " ")) が失敗 status=\(p.terminationStatus): \(output)")
        }
        return (p.terminationStatus, output)
    }
}

/// サイズ上限つきの追記ログ。上限を超えたら .1 に退避して書き直す。
/// 標準エラーには書かない(launchd がそれを helper.stderr.log に上限なしで溜めるため。そちらはクラッシュ時の出力用)。
final class HelperLog: @unchecked Sendable {
    let url: URL
    let maxBytes = 1_000_000
    private let lock = NSLock()

    init(url: URL) { self.url = url }

    func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let fm = FileManager.default
        do {
            if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int, size > maxBytes {
                let old = url.appendingPathExtension("1")
                try? fm.removeItem(at: old)
                try fm.moveItem(at: url, to: old)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            FileHandle.standardError.write(Data("helper.log に書けない: \(error)\n".utf8))
        }
    }
}

enum DisplayWatcher {
    @MainActor private static var handler: (() -> Void)?

    /// 戻り値は CGDisplayRegisterReconfigurationCallback の結果(0 が成功)。
    @MainActor
    static func start(_ onChange: @escaping () -> Void) -> CGError {
        handler = onChange
        return CGDisplayRegisterReconfigurationCallback(
            { _, flags, _ in
                // 変更の開始(beginConfiguration)と終了の両方で呼ばれる。終了だけ拾う。
                guard !flags.contains(.beginConfigurationFlag) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { DisplayWatcher.handler?() } }
            }, nil)
    }
}

/// ~/Library/Preferences/com.apple.universalaccess.plist の書き換えを kqueue で待つ。
/// cfprefsd は rename で置き換えるので、delete / rename を受けたら新しいファイルを開き直す。
/// 値が変わったときだけに絞ると取りこぼす: 色の変更→リセットが1回の書き出しにまとまると、
/// ファイル上の値は変わらないのにテーマは消えている(実測)。書き換えのたびに通知する。
@MainActor
final class PrefsWatcher {
    let path = NSHomeDirectory() + "/Library/Preferences/com.apple.universalaccess.plist"
    /// 第2引数はポインターのサイズ・色が前回から変わったか(ログ用)。
    let onChange: (CursorEnvironment, Bool) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var last = CursorEnvironment.current()

    init(onChange: @escaping (CursorEnvironment, Bool) -> Void) { self.onChange = onChange }

    func start(checkNow: Bool = false) {
        source?.cancel()
        source = nil
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // まだ一度もアクセシビリティ設定を変えていないとファイルが無い。現れるまで待つ手段として少し後に開き直す。
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.start(checkNow: true) }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let reopen = !src.data.intersection([.delete, .rename]).isEmpty
            self.check()
            if reopen {
                // 開き直した直後の check は同じ書き換えの重複になるので start(checkNow: false)。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.start(checkNow: false) }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        if checkNow { check() }
    }

    private func check() {
        CFPreferencesAppSynchronize("com.apple.universalaccess" as CFString)
        let env = CursorEnvironment.current()
        let changed = env.cursorSize != last.cursorSize || env.cursorIsCustomized != last.cursorIsCustomized
        last = env
        onChange(env, changed)
    }
}
