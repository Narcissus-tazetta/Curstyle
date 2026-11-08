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
        --fail-after N             失敗注入: N 回の登録の後、次の登録を1回だけ失敗させる(ロールバックを確かめる)
        --kill-after N             失敗注入: N 回の登録の後、プロセスを SIGKILL する(restore を確かめる)
      make-theme <dir> [--labels]  テスト画像をテーマディレクトリとして書き出す。--labels は全 cursor.N に番号を描いたテーマ
      restore                      スナップショットから標準へ戻す(テーマのコードを通らない独立経路)
      reset-system                 スナップショットを使わずに OS の標準へ戻す(ポインター色リセット時の再登録と同じ処理)
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
        guard let dir = args.first else { fail("make-theme には書き出し先のディレクトリが要る\n\(usage)", code: 2) }
        let theme = labels ? try TestTheme.makeLabeled() : try TestTheme.make(keys: TestTheme.keys, animated: false)
        try theme.write(directory: URL(fileURLWithPath: dir, isDirectory: true))
        print("書き出した: \(dir)(\(theme.cursors.count) 件)")

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
        var backend: CursorBackend = try CGSBackend()
        if let n = failAfter { backend = FaultInjectingBackend(base: backend, fault: .failRegister(after: n)) }
        if let n = killAfter { backend = FaultInjectingBackend(base: backend, fault: .killProcess(after: n)) }
        let report = try CursorEngine(backend: backend, store: store).apply(theme)
        print("テーマ \(report.themeName)")
        printResults(report.results)
        if let failure = report.failure {
            print("適用失敗: \(failure)")
            print("ロールバック:")
            if let rb = report.rollback { printRestore(rb) }
            exit(1)
        }
        print("適用完了(読み戻しは一致。画面への反映は目視で確認すること)")

    case "reset-system":
        try store.lock()
        let report = try SystemReset.run(store: store)
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
        let report = try Recovery(backend: try CGSBackend(), store: store).restore()
        printRestore(report)
        exit(report.succeeded ? 0 : 1)

    default:
        print(usage)
        exit(2)
    }
} catch {
    fail("\(error)")
}
