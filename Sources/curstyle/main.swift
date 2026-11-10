import CursorKit
import Foundation

let usage = """
    usage: curstyle <command>
      diagnose                     自己診断(OS・シンボル・ポインター色・スナップショット・名前ごとの状態)
      report [file]                不具合報告用の診断レポートを書き出す(既定は ./curstyle-report-<日時>.txt、- で標準出力)
      status                       名前ごとの状態を全件表示
      snapshot                     現在の標準画像をスナップショットに取り込む(適用はしない)
      apply --test [keys] [--animated]   テスト画像を適用する。keys は arrow,ibeam,link(既定は全部)
      apply <theme-dir>            theme.json のテーマを適用する
        --backend overlay          本物を隠して自前で描く方式で適用する(CGSBackend が使えない OS 向け。ヘルパーが描く)
        --fail-after N             失敗注入: N 回の登録の後、次の登録を1回だけ失敗させる(ロールバックを確かめる)
        --kill-after N             失敗注入: N 回の登録の後、プロセスを SIGKILL する(restore を確かめる)
      make-theme <dir> [--labels | --overlay-check]  テスト画像をテーマディレクトリとして書き出す。
                                   --labels は全 cursor.N に番号を描いたテーマ、--overlay-check は役割ごとに単色の検証用テーマ
      import <windows-dir> <theme-dir> [--scale N] [--name NAME]
                                   Windows のカーソルフォルダ(Normal.ani など)をテーマディレクトリに変換する。
                                   --scale は画像の何ピクセルを 1pt とみなすか(既定 1。2 は Retina で原寸だが小さく見える)
      restore                      スナップショットから標準へ戻す(テーマのコードを通らない独立経路)。overlay なら描画を止める
      reset-system                 スナップショットを使わずに OS の標準へ戻す(ポインター色リセット時の再登録と同じ処理)
      helper install               ログイン時に起動する自動再適用ヘルパーを LaunchAgent として登録し、起動する
      helper uninstall             ヘルパーを止めて登録を消す
      helper status                ヘルパーの登録状態・停止理由・直近のログ
      helper resume                回数上限などで止まったヘルパーを再開する
      helper run                   ヘルパー本体(launchd から起動される)
    """

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
}

func printResults(_ results: [NameResult]) {
    for r in results {
        let mark = r.outcome == .failed || !r.readbackMatches ? "NG" : "ok"
        print(
            "  [\(mark)] \(r.outcome.rawValue)\t\(r.name)\t読み戻し一致=\(r.readbackMatches)\(r.detail.map { "\t\($0)" } ?? "")"
        )
    }
}

func printRestore(_ report: RestoreReport) {
    let changed = report.results.filter { $0.outcome != .unchanged }
    printResults(changed)
    print("  変更なし \(report.results.count - changed.count) 件")
    print(report.succeeded ? "復元: 全件の読み戻しがスナップショットと一致" : "復元: 失敗あり(上の NG を参照)")
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(2)
}
args.removeFirst()

@MainActor func takeOption(_ name: String) -> Int? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count, let n = Int(args[i + 1]), n >= 0 else { fail("\(name) には 0 以上の整数が要る") }
    args.removeSubrange(i...(i + 1))
    return n
}

@MainActor func takeValue(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count else { fail("\(name) には値が要る") }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}

/// ヘルパーが合図を受けて overlay を始めた(止めた)ことを helper.json で確かめる。最大5秒待つ。
func waitForOverlay(store: SnapshotStore, running: Bool, since: Date) -> Bool {
    // helper.json の時刻は秒単位で保存される。
    let since = Date(timeIntervalSince1970: since.timeIntervalSince1970.rounded(.down))
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if let status = try? store.loadHelperState().overlay {
            if running, status.running, let s = status.startedAt, s >= since {
                print("ヘルパーが描画を始めた(照合表 \(status.matcherEntries) 件)。見た目は目視で確認すること")
                return true
            }
            if running, let r = status.stoppedReason, let s = status.stoppedAt, s >= since {
                print("ヘルパーが描画を始められなかった: \(r)")
                return false
            }
            if !running, !status.running {
                print("ヘルパーが描画を止めた(本物のカーソルに戻った)")
                return true
            }
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
    print(
        running
            ? "5 秒待ってもヘルパーが描画を始めない。`curstyle helper status` を確認すること(未インストールなら `curstyle helper install`)"
            : "5 秒待ってもヘルパーが描画を止めない。`curstyle helper status` を確認すること")
    return false
}

@MainActor func takeFlag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

do {
    // 試験用に別の置き場所を使えるようにする(既定は ~/Library/Application Support/Curstyle)。
    let store =
        try ProcessInfo.processInfo.environment["CURSTYLE_HOME"].map {
            try SnapshotStore(root: URL(fileURLWithPath: $0, isDirectory: true))
        } ?? SnapshotStore()
    switch command {
    case "diagnose":
        let report = Diagnostics.run(store: store)
        for item in report.items {
            print("[\(item.level.rawValue)] \(item.title): \(item.detail)")
        }
        print("[情報] ヘルパーの登録: \(Helper.launchdState())")
        exit(report.hasProblem ? 1 : 0)

    case "report":
        let text = Diagnostics.fullReport(store: store)
        if args.first == "-" {
            print(text, terminator: "")
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let path = args.first ?? "curstyle-report-\(formatter.string(from: Date())).txt"
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            print("書き出した: \(path)")
        }

    case "make-theme":
        let labels = takeFlag("--labels")
        let overlayCheck = takeFlag("--overlay-check")
        guard let dir = args.first else { fail("make-theme には書き出し先のディレクトリが要る\n\(usage)", code: 2) }
        let theme =
            overlayCheck
            ? TestTheme.makeOverlayCheck()
            : labels ? try TestTheme.makeLabeled() : try TestTheme.make(keys: TestTheme.keys, animated: false)
        try theme.write(directory: URL(fileURLWithPath: dir, isDirectory: true))
        print("書き出した: \(dir)(\(theme.cursors.count) 件)")

    case "import":
        let scale = takeOption("--scale") ?? 1
        let name = takeValue("--name")
        guard args.count == 2 else { fail("import には Windows のフォルダと書き出し先が要る\n\(usage)", code: 2) }
        let source = URL(fileURLWithPath: args[0], isDirectory: true)
        let result = try WindowsCursorImporter.importTheme(
            directory: source, name: name ?? source.lastPathComponent, pixelsPerPoint: scale)
        try result.theme.write(directory: URL(fileURLWithPath: args[1], isDirectory: true))
        print("書き出した: \(args[1])(\(result.theme.cursors.count) 件)")
        if !result.skippedFiles.isEmpty {
            print("対応する macOS のカーソルが無いので取り込まなかった: \(result.skippedFiles.sorted().joined(separator: ", "))")
        }

    case "status":
        let engine = CursorEngine(backend: try CGSBackend(), store: store)
        for s in try engine.states() {
            print("\(s.name)\t\(s.state.rawValue)\t\(s.hash)")
        }

    case "snapshot":
        try store.lock()
        let engine = CursorEngine(backend: try CGSBackend(), store: store)
        try engine.refreshSnapshot()
        print("スナップショットを更新した: \(store.root.path)/snapshot")

    case "apply":
        let backendName = takeValue("--backend") ?? "cgs"
        guard backendName == "cgs" || backendName == "overlay" else { fail("--backend は cgs か overlay", code: 2) }
        let failAfter = takeOption("--fail-after")
        let killAfter = takeOption("--kill-after")
        let animated = takeFlag("--animated")
        let theme: CursorTheme
        if takeFlag("--test") {
            let keys = args.first.map { $0.split(separator: ",").map(String.init) } ?? TestTheme.keys
            theme = try TestTheme.make(keys: keys, animated: animated)
        } else if let dir = args.first {
            theme = try CursorTheme.load(directory: URL(fileURLWithPath: dir))
        } else {
            fail("apply には --test かテーマディレクトリが要る\n\(usage)", code: 2)
        }
        try store.lock()
        if backendName == "overlay" {
            let started = Date()
            for note in try OverlayActivation.apply(theme, store: store) { print("  \(note)") }
            store.unlock()
            print("テーマ \(theme.name) を overlay 方式で適用した。描画はヘルパーが行う")
            exit(waitForOverlay(store: store, running: true, since: started) ? 0 : 1)
        }
        var backend: CursorBackend = try CGSBackend()
        if let n = failAfter { backend = FaultInjectingBackend(base: backend, fault: .failRegister(after: n)) }
        if let n = killAfter { backend = FaultInjectingBackend(base: backend, fault: .killProcess(after: n)) }
        let report = try CursorEngine(backend: backend, store: store).apply(theme)
        // overlay から切り替えた場合に、ヘルパーの描画を止めさせる。
        OverlayActivation.postChanged()
        print("テーマ \(report.themeName)")
        printResults(report.results)
        if let failure = report.failure {
            print("適用失敗: \(failure)")
            print("ロールバック:")
            if let rb = report.rollback { printRestore(rb) }
            if OverlaySymbols.missing().isEmpty {
                print("CGSBackend で適用できない OS なら `curstyle apply --backend overlay <テーマ>` を使える(本物を隠して自前で描く方式)")
            }
            exit(1)
        }
        print("適用完了(読み戻しは一致。画面への反映は目視で確認すること)")

    case "reset-system":
        try store.lock()
        let report = try SystemReset.run(store: store)
        OverlayActivation.postChanged()
        for name in report.before.keys.sorted() where report.before[name] != report.after[name] {
            print("  \(name)\t\(report.before[name]!) → \(report.after[name]!)")
        }
        if !report.failures.isEmpty {
            print("登録し直せなかった名前: \(report.failures.joined(separator: ", "))")
            print("`curstyle restore`(スナップショットがある場合)か再ログインで戻すこと")
            exit(1)
        }
        print("OS の標準へ戻した(読み戻しは変化した名前のみ表示。画面への反映は目視で確認すること)")

    case "restore":
        try store.lock()
        if try store.loadJournal().backend == .overlay {
            let started = Date()
            try store.saveJournal(.clean)
            OverlayActivation.postChanged()
            store.unlock()
            print("overlay 方式の適用を解除した")
            exit(waitForOverlay(store: store, running: false, since: started) ? 0 : 1)
        }
        let report = try Recovery(backend: try CGSBackend(), store: store).restore()
        printRestore(report)
        exit(report.succeeded ? 0 : 1)

    case "helper":
        switch args.first {
        case "run":
            Helper.run(store: store)
        case "install":
            guard store.root == SnapshotStore.defaultRoot else {
                fail("CURSTYLE_HOME を指定したままでは install しない(ヘルパーは既定の置き場所を使う)")
            }
            guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
                fail("自分の実行ファイルのパスを取れない")
            }
            // 入れ直しはヘルパーの起動に数えない(overlay のクラッシュの繰り返しの検知と区別する)。
            var helperState = try store.loadHelperState()
            helperState.overlay?.launchStarts = []
            try store.saveHelperState(helperState)
            let installed = try Helper.install(executable: exe)
            print("登録した: \(Helper.plistURL.path)")
            print("実行ファイル: \(installed.path)(\(exe.path) の写し。更新したら install し直すこと)")
            print(Helper.launchdState())
        case "uninstall":
            try Helper.uninstall()
            print("ヘルパーを止めて登録を消した")
        case "resume":
            try AutoReapply.resume(store: store)
            print("再開した(次のイベントか、ヘルパーの再起動で確認する)")
        case "status":
            print("launchd: \(Helper.launchdState())")
            let state = try store.loadHelperState()
            print("停止: \(state.stoppedReason.map { "\($0)(\(state.stoppedAt!))" } ?? "していない")")
            print("直近の確認: \(state.lastCheckAt.map { "\($0)" } ?? "-") \(state.lastResult ?? "")")
            let now = Date()
            print(
                "再適用: 直近1時間 \(state.reappliedAt.filter { now.timeIntervalSince($0) < 3600 }.count) 回、うち原因不明の消失で直近10分 \(state.unexplainedAt.filter { now.timeIntervalSince($0) < 600 }.count) 回"
            )
            let logURL = store.root.appendingPathComponent("helper.log")
            if let text = try? String(contentsOf: logURL, encoding: .utf8) {
                print("--- helper.log(末尾10行)")
                for line in text.split(separator: "\n").suffix(10) { print(line) }
            }
        default:
            fail("helper には run / install / uninstall / status / resume のどれかが要る\n\(usage)", code: 2)
        }

    default:
        print(usage)
        exit(2)
    }
} catch {
    fail("\(error)")
}
