import CoreGraphics
import Foundation

/// 標準画像を取得したときの状態。標準画像はログイン時とポインター色変更時で異なるため、
/// 「いつ・どの設定で」取ったかを一緒に残す。
public struct CursorEnvironment: Codable, Sendable, Hashable {
    public var osVersion: String
    public var cursorIsCustomized: Bool?
    public var cursorSize: Double?

    public static func current() -> CursorEnvironment {
        let domain = "com.apple.universalaccess" as CFString
        func pref(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain) }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return CursorEnvironment(
            osVersion: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            cursorIsCustomized: (pref("cursorIsCustomized") as? NSNumber)?.boolValue,
            cursorSize: (pref("mouseDriverCursorSize") as? NSNumber)?.doubleValue)
    }
}

public struct SnapshotEntry: Codable, Sendable {
    public struct Registered: Codable, Sendable {
        public var width: Double
        public var height: Double
        public var hotspotX: Double
        public var hotspotY: Double
        public var frameCount: Int
        public var frameDuration: Double
        public var imageFiles: [String]
    }

    /// nil は「取得時に未登録だった」。復元ではその名前を削除する。
    public var registered: Registered?
    public var hash: String
    public var capturedAt: Date
    public var environment: CursorEnvironment
}

public struct SnapshotManifest: Codable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var updatedAt: Date
    public var entries: [String: SnapshotEntry]
}

/// 適用の途中経過。クラッシュ後でも「どの名前に何を登録したか」が分かるよう、登録の前に書く。
public struct Journal: Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case clean
        case applying
        case applied
    }

    /// cgs: 登録名にテーマを登録する。overlay: ヘルパーが本物を隠して自前で描く(登録はしない)。
    public enum Backend: String, Codable, Sendable {
        case cgs
        case overlay
    }

    public var status: Status
    public var themeName: String?
    /// 名前 → 登録した(しようとした)内容のハッシュ。overlay では空。
    public var intended: [String: String]
    public var updatedAt: Date
    public var backend: Backend = .cgs

    public init(
        status: Status, themeName: String?, intended: [String: String], updatedAt: Date, backend: Backend = .cgs
    ) {
        self.status = status
        self.themeName = themeName
        self.intended = intended
        self.updatedAt = updatedAt
        self.backend = backend
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Status.self, forKey: .status)
        themeName = try c.decodeIfPresent(String.self, forKey: .themeName)
        intended = try c.decode([String: String].self, forKey: .intended)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        backend = try c.decodeIfPresent(Backend.self, forKey: .backend) ?? .cgs
    }

    public static let clean = Journal(status: .clean, themeName: nil, intended: [:], updatedAt: Date())
}

/// スナップショットとジャーナルのディスク上の置き場所。
/// ~/Library/Application Support/Curstyle/{snapshot/, journal.json, lock}
public final class SnapshotStore {
    public let root: URL
    var snapshotDir: URL { root.appendingPathComponent("snapshot", isDirectory: true) }
    var manifestURL: URL { snapshotDir.appendingPathComponent("manifest.json") }
    var journalURL: URL { root.appendingPathComponent("journal.json") }
    private var lockFD: Int32 = -1

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Curstyle", isDirectory: true)
    }

    public init(root: URL = SnapshotStore.defaultRoot) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// 同時に2つのプロセスが適用・復元しないための排他。プロセス終了で自動的に解放される。
    public func lock() throws {
        let path = root.appendingPathComponent("lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw CursorKitError.io("ロックファイルを開けない: \(path) errno=\(errno)") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw CursorKitError.busy("別の curstyle が適用・復元中(\(path) がロックされている)")
        }
        lockFD = fd
    }

    /// 常駐プロセスはロックを持ち続けると CLI の操作を塞ぐので、操作のたびに取って放す。
    public func unlock() {
        guard lockFD >= 0 else { return }
        close(lockFD)
        lockFD = -1
    }

    public func withLock<T>(_ body: () throws -> T) throws -> T {
        try lock()
        defer { unlock() }
        return try body()
    }

    deinit {
        unlock()
    }

    // MARK: active theme

    /// 最後に適用したテーマの写し。自動再適用はこれを使う(元のディレクトリが動いても壊れないように)。
    var activeThemeURL: URL { root.appendingPathComponent("active-theme", isDirectory: true) }

    public func saveActiveTheme(_ theme: CursorTheme) throws {
        let fm = FileManager.default
        let staging = root.appendingPathComponent("active-theme.staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try theme.write(directory: staging)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
        if fm.fileExists(atPath: activeThemeURL.path) {
            _ = try fm.replaceItemAt(activeThemeURL, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: activeThemeURL)
        }
    }

    public func loadActiveTheme() throws -> CursorTheme? {
        guard FileManager.default.fileExists(atPath: activeThemeURL.path) else { return nil }
        return try CursorTheme.load(directory: activeThemeURL)
    }

    // MARK: journal

    public func loadJournal() throws -> Journal {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return .clean }
        return try decoder.decode(Journal.self, from: Data(contentsOf: journalURL))
    }

    public func saveJournal(_ journal: Journal) throws {
        var j = journal
        j.updatedAt = Date()
        try encoder.encode(j).write(to: journalURL, options: .atomic)
    }

    // MARK: snapshot

    public var hasSnapshot: Bool { FileManager.default.fileExists(atPath: manifestURL.path) }

    public func loadManifest() throws -> SnapshotManifest? {
        guard hasSnapshot else { return nil }
        let manifest = try decoder.decode(SnapshotManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == SnapshotManifest.currentVersion else {
            throw CursorKitError.snapshot("未対応の形式 version=\(manifest.version)")
        }
        return manifest
    }

    public func loadRep(_ entry: SnapshotEntry) throws -> CursorRep? {
        guard let r = entry.registered else { return nil }
        let images = try r.imageFiles.map { try readPNG(at: snapshotDir.appendingPathComponent($0)) }
        return CursorRep(
            size: CGSize(width: r.width, height: r.height), hotspot: CGPoint(x: r.hotspotX, y: r.hotspotY),
            frameCount: r.frameCount, frameDuration: r.frameDuration, images: images)
    }

    /// 全エントリを書き直し、ディレクトリごと置き換える。書いた後に読み直してハッシュを照合し、
    /// 一致しなければ置き換えない(戻せないスナップショットを残さない)。
    public func save(entries: [String: (result: ReadResult, capturedAt: Date, environment: CursorEnvironment)]) throws {
        let fm = FileManager.default
        let staging = root.appendingPathComponent("snapshot.staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var manifestEntries: [String: SnapshotEntry] = [:]
        for (name, e) in entries {
            var registered: SnapshotEntry.Registered?
            var hash = "-"
            if let rep = e.result.rep {
                var normalized = rep
                normalized.images = rep.images.map(normalizedImage)
                hash = normalized.contentHash
                var files: [String] = []
                for (i, image) in normalized.images.enumerated() {
                    let file = "\(name).\(i).png"
                    try writePNG(image, to: staging.appendingPathComponent(file))
                    files.append(file)
                }
                registered = .init(
                    width: rep.size.width, height: rep.size.height, hotspotX: rep.hotspot.x,
                    hotspotY: rep.hotspot.y, frameCount: rep.frameCount, frameDuration: rep.frameDuration,
                    imageFiles: files)
            }
            manifestEntries[name] = SnapshotEntry(
                registered: registered, hash: hash, capturedAt: e.capturedAt, environment: e.environment)
        }
        let manifest = SnapshotManifest(
            version: SnapshotManifest.currentVersion, updatedAt: Date(), entries: manifestEntries)
        try encoder.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)

        for (name, entry) in manifestEntries {
            guard let r = entry.registered else { continue }
            let images = try r.imageFiles.map { try readPNG(at: staging.appendingPathComponent($0)) }
            let reloaded = CursorRep(
                size: CGSize(width: r.width, height: r.height), hotspot: CGPoint(x: r.hotspotX, y: r.hotspotY),
                frameCount: r.frameCount, frameDuration: r.frameDuration, images: images)
            guard reloaded.contentHash == entry.hash else {
                try? fm.removeItem(at: staging)
                throw CursorKitError.snapshot("\(name) を保存→読み直すとハッシュが変わる(\(entry.hash) → \(reloaded.contentHash))")
            }
        }

        if fm.fileExists(atPath: snapshotDir.path) {
            _ = try fm.replaceItemAt(snapshotDir, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: snapshotDir)
        }
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
