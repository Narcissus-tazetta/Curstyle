import CoreGraphics
import Foundation

/// アプリが管理するテーマの置き場(<root>/themes/<id>/theme.json)。
/// 適用中のテーマは SnapshotStore の active-theme に別に写すので、ここで消しても自動再適用は壊れない。
public final class ThemeLibrary: @unchecked Sendable {
    public struct Entry: Identifiable, Sendable {
        public var id: String
        public var directory: URL
        public var theme: CursorTheme
        public var addedAt: Date
        public var undoCount: Int = 0
        /// テーマの中身の指紋。active-theme と比べて「適用中か」を判断する。
        public var fingerprint: String
    }

    public let root: URL

    public init(root: URL = SnapshotStore.defaultRoot.appendingPathComponent("themes", isDirectory: true)) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// 読めないテーマは捨てずに errors に入れて返す(利用者に見せて、消すか直すかを選んでもらう)。
    public func load() -> (entries: [Entry], errors: [(directory: URL, message: String)]) {
        let fm = FileManager.default
        let dirs =
            (try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        var entries: [Entry] = []
        var errors: [(URL, String)] = []
        for dir in dirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            do {
                let theme = try CursorTheme.load(directory: dir)
                let added = (try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                entries.append(
                    Entry(
                        id: dir.lastPathComponent, directory: dir, theme: theme, addedAt: added,
                        undoCount: try historyCount(in: dir), fingerprint: theme.fingerprint))
            } catch {
                errors.append((dir, "\(error)"))
            }
        }
        entries.sort { $0.addedAt < $1.addedAt }
        return (entries, errors)
    }

    /// 検証を通ったテーマだけを置く。書き出し途中のディレクトリが一覧に出ないよう、隠しの一時名で書いてから rename する。
    @discardableResult
    public func add(_ theme: CursorTheme) throws -> Entry {
        _ = try theme.resolvedPlan()
        let id = UUID().uuidString
        let staging = root.appendingPathComponent(".staging-\(id)", isDirectory: true)
        let dir = root.appendingPathComponent(id, isDirectory: true)
        do {
            try theme.write(directory: staging)
            try FileManager.default.moveItem(at: staging, to: dir)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return Entry(id: id, directory: dir, theme: theme, addedAt: Date(), fingerprint: theme.fingerprint)
    }

    public func remove(_ entry: Entry) throws {
        try FileManager.default.trashItem(at: entry.directory, resultingItemURL: nil)
    }

    public func rename(_ entry: Entry, to name: String) throws -> Entry {
        var theme = entry.theme
        theme.name = name
        return try update(entry, with: theme)
    }

    /// 別の場所に履歴ごと書いてから差し替え、保存失敗時は元のテーマと履歴を保つ。
    @discardableResult
    public func update(_ entry: Entry, with theme: CursorTheme) throws -> Entry {
        try replace(entry, with: theme, undoing: false)
    }

    @discardableResult
    public func undo(_ entry: Entry) throws -> Entry {
        let count = try historyCount(in: entry.directory)
        let previous = try CursorTheme.load(directory: historyURL(in: entry.directory, index: count))
        return try replace(entry, with: previous, undoing: true)
    }

    private func historyURL(in directory: URL, index: Int) -> URL {
        directory.appendingPathComponent(".undo", isDirectory: true)
            .appendingPathComponent(String(format: "%08d", index), isDirectory: true)
    }

    private func historyCount(in directory: URL) throws -> Int {
        let history = directory.appendingPathComponent(".undo", isDirectory: true)
        guard FileManager.default.fileExists(atPath: history.path) else { return 0 }
        return try FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: nil).count
    }

    private func replace(_ entry: Entry, with theme: CursorTheme, undoing: Bool) throws -> Entry {
        _ = try theme.resolvedPlan()
        let fm = FileManager.default
        let count = try historyCount(in: entry.directory)
        let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try theme.write(directory: staging)
            let history = entry.directory.appendingPathComponent(".undo", isDirectory: true)
            if count > 0 {
                try fm.copyItem(at: history, to: staging.appendingPathComponent(".undo", isDirectory: true))
            }
            if undoing {
                try fm.removeItem(at: historyURL(in: staging, index: count))
            } else {
                let previous = try CursorTheme.load(directory: entry.directory)
                try previous.write(directory: historyURL(in: staging, index: count + 1))
            }
            try fm.setAttributes([.creationDate: entry.addedAt], ofItemAtPath: staging.path)
            // 履歴も同じディレクトリ内で差し替え、保存失敗で履歴だけが進むことを防ぐ。
            _ = try fm.replaceItemAt(entry.directory, withItemAt: staging)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        var updated = entry
        updated.theme = theme
        updated.undoCount = count + (undoing ? -1 : 1)
        updated.fingerprint = theme.fingerprint
        return updated
    }
}

extension CursorTheme {
    /// 名前を除いた中身(キーと各カーソルの contentHash)の指紋。
    public var fingerprint: String {
        cursors.keys.sorted().map { "\($0)=\(cursors[$0]!.contentHash)" }.joined(separator: ";")
    }

    /// 取り込み元の形式を見て読む。.cape ファイル、Curstyle のテーマ(theme.json)、Windows のカーソルフォルダ。
    /// skipped は取り込まなかったファイル・識別子(利用者に見せる)。
    public static func importSource(_ url: URL, name: String?, pixelsPerPoint: Int) throws -> (
        theme: CursorTheme, skipped: [String], adjustments: [String]
    ) {
        if url.pathExtension.lowercased() == "cape" {
            let result = try CapeImporter.importTheme(file: url, name: name)
            return (result.theme, result.skipped, result.adjustments)
        }
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("theme.json").path) {
            var theme = try CursorTheme.load(directory: url)
            if let name { theme.name = name }
            var adjustments: [String] = []
            for key in theme.cursors.keys.sorted() {
                let imported = try theme.cursors[key]!.importingAnimation()
                theme.cursors[key] = imported.rep
                if let adjustment = imported.adjustment { adjustments.append("\(key): \(adjustment)") }
            }
            return (theme, [], adjustments)
        }
        let result = try WindowsCursorImporter.importTheme(
            directory: windowsCursorDirectory(in: url),
            name: name ?? url.deletingPathExtension().lastPathComponent, pixelsPerPoint: pixelsPerPoint)
        return (result.theme, result.skippedFiles, result.adjustments)
    }

    /// 配布されている Windows のテーマは `<名前>.cursor/Cursors/` のように1階層下に .ani / .cur を置いていることが多い。
    /// 直下に無ければ、.ani / .cur を含むサブフォルダから選ぶ。アニメ版(Cursors)と静止画版(Static)を
    /// 並べて配る作者が多いので、.ani を含むものを優先する。それでも1つに決まらなければ選ばない(利用者がフォルダを選び直す)。
    static func windowsCursorDirectory(in directory: URL) -> URL {
        let fm = FileManager.default
        func files(_ dir: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        }
        func has(_ dir: URL, _ exts: Set<String>) -> Bool {
            files(dir).contains { exts.contains($0.pathExtension.lowercased()) }
        }
        guard !has(directory, ["ani", "cur"]) else { return directory }
        let subdirs =
            (try? fm.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let candidates = subdirs.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && has($0, ["ani", "cur"])
        }
        let animated = candidates.filter { has($0, ["ani"]) }
        if animated.count == 1 { return animated[0] }
        return candidates.count == 1 ? candidates[0] : directory
    }
}

extension CursorRep {
    /// プレビュー用に、いちばん高い解像度の画像をフレームごとに切り出す。先頭フレームが上(登録形式と同じ)。
    public func previewFrames() -> (frames: [CGImage], scale: Int) {
        guard let image = images.max(by: { $0.width < $1.width }) else { return ([], 1) }
        let scale = max(1, Int(Double(image.width) / size.width))
        let frameHeight = image.height / max(frameCount, 1)
        let frames = (0..<frameCount).compactMap {
            image.cropping(to: CGRect(x: 0, y: $0 * frameHeight, width: image.width, height: frameHeight))
        }
        return (frames, scale)
    }
}
