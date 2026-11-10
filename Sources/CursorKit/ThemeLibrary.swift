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
                        fingerprint: theme.fingerprint))
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
        try theme.write(directory: entry.directory)
        var updated = entry
        updated.theme = theme
        updated.fingerprint = theme.fingerprint
        return updated
    }
}

extension CursorTheme {
    /// 名前を除いた中身(キーと各カーソルの contentHash)の指紋。
    public var fingerprint: String {
        cursors.keys.sorted().map { "\($0)=\(cursors[$0]!.contentHash)" }.joined(separator: ";")
    }

    /// 取り込み元がどちらの形式かを見て読む。Curstyle のテーマ(theme.json)か、Windows のカーソルフォルダ。
    public static func importFolder(_ directory: URL, name: String?, pixelsPerPoint: Int) throws -> (
        theme: CursorTheme, skippedFiles: [String]
    ) {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("theme.json").path) {
            var theme = try CursorTheme.load(directory: directory)
            if let name { theme.name = name }
            return (theme, [])
        }
        let result = try WindowsCursorImporter.importTheme(
            directory: windowsCursorDirectory(in: directory),
            name: name ?? directory.deletingPathExtension().lastPathComponent, pixelsPerPoint: pixelsPerPoint)
        return (result.theme, result.skippedFiles)
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
