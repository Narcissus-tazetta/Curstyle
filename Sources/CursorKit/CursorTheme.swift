import CoreGraphics
import Foundation

/// キーは CursorCatalog.targets(for:) が受け付ける名前(arrow / ibeam / pointingHand / cursor.N など)。
public struct CursorTheme: Sendable {
    public var name: String
    public var cursors: [String: CursorRep]

    public init(name: String, cursors: [String: CursorRep]) {
        self.name = name
        self.cursors = cursors
    }

    /// 検証済みの (登録名, 内容) の並び。1つでも不正なら何も適用しない。
    public func resolvedPlan() throws -> [(name: String, rep: CursorRep)] {
        guard !cursors.isEmpty else { throw CursorKitError.theme(L10n.text("カーソルが1つも無い")) }
        var plan: [String: (key: String, rep: CursorRep)] = [:]
        for (key, rep) in cursors.sorted(by: { $0.key < $1.key }) {
            do {
                try rep.validate()
            } catch {
                throw CursorKitError.theme("\(key): \(error)")
            }
            for target in try CursorCatalog.targets(for: key) {
                if let other = plan[target] {
                    throw CursorKitError.theme(
                        L10n.text(
                            "{0} と {1} が同じ {2} を指している", String(describing: key), String(describing: other.key),
                            String(describing: target)))
                }
                plan[target] = (key, rep)
            }
        }
        return plan.keys.sorted().map { ($0, plan[$0]!.rep) }
    }

    func visiblePlan() throws -> [(name: String, rep: CursorRep)] {
        let plan = try resolvedPlan()
        var checked: [ObjectIdentifier: Set<Int>] = [:]
        for (name, rep) in plan {
            for image in rep.images where checked[ObjectIdentifier(image), default: []].insert(rep.frameCount).inserted
            {
                let height = image.height / rep.frameCount
                for index in 0..<rep.frameCount {
                    let rect = CGRect(x: 0, y: index * height, width: image.width, height: height)
                    guard let frame = image.cropping(to: rect), frame.hasVisibleCursorPixels else {
                        throw CursorKitError.theme(
                            L10n.text("{0} の {1} コマ目が透明なので適用できません。", name, String(index + 1)))
                    }
                }
            }
        }
        return plan
    }

    /// テーマディレクトリ: theme.json と PNG。
    /// ```
    /// { "name": "...", "cursors": { "arrow": { "size": [w, h], "hotspot": [x, y],
    ///   "frameCount": 1, "frameDuration": 0, "images": ["arrow@1x.png", "arrow@2x.png"],
    ///   "source": "arrow@source.png" } } }
    /// ```
    /// source は省略できる(CursorRep.source)。
    public static func load(directory: URL) throws -> CursorTheme {
        struct Entry: Decodable {
            var size: [Double]
            var hotspot: [Double]
            var frameCount: Int?
            var frameDuration: Double?
            var images: [String]
            var source: String?
        }
        struct File: Decodable {
            var name: String
            var cursors: [String: Entry]
        }
        let jsonURL = directory.appendingPathComponent("theme.json")
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: Data(contentsOf: jsonURL))
        } catch {
            throw CursorKitError.theme(
                L10n.text("{0} を読めない: {1}", String(describing: jsonURL.path), String(describing: error)))
        }
        var cursors: [String: CursorRep] = [:]
        for (key, e) in file.cursors {
            guard e.size.count == 2, e.hotspot.count == 2 else {
                throw CursorKitError.theme(L10n.text("{0}: size と hotspot は [x, y] の2要素", String(describing: key)))
            }
            let images = try e.images.map { try readPNG(at: directory.appendingPathComponent($0)) }
            cursors[key] = CursorRep(
                size: CGSize(width: e.size[0], height: e.size[1]), hotspot: CGPoint(x: e.hotspot[0], y: e.hotspot[1]),
                frameCount: e.frameCount ?? 1, frameDuration: e.frameDuration ?? 0, images: images,
                source: try e.source.map { try readPNG(at: directory.appendingPathComponent($0)) })
        }
        return CursorTheme(name: file.name, cursors: cursors)
    }
}

extension CursorTheme {
    /// load(directory:) で読める形(theme.json と <key>@<倍率>x.png)で書き出す。既存のファイルは上書きする。
    public func write(directory: URL) throws {
        struct Entry: Encodable {
            var size: [Double]
            var hotspot: [Double]
            var frameCount: Int
            var frameDuration: Double
            var images: [String]
            var source: String?
        }
        struct File: Encodable {
            var name: String
            var cursors: [String: Entry]
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var entries: [String: Entry] = [:]
        for (key, rep) in cursors {
            var files: [String] = []
            for image in rep.images {
                let file = "\(key)@\(Int(Double(image.width) / rep.size.width))x.png"
                try writePNG(image, to: directory.appendingPathComponent(file))
                files.append(file)
            }
            let sourceFile = rep.source.map { _ in "\(key)@source.png" }
            if let source = rep.source, let sourceFile {
                try writePNG(source, to: directory.appendingPathComponent(sourceFile))
            }
            entries[key] = Entry(
                size: [rep.size.width, rep.size.height], hotspot: [rep.hotspot.x, rep.hotspot.y],
                frameCount: rep.frameCount, frameDuration: rep.frameDuration, images: files, source: sourceFile)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(File(name: name, cursors: entries)).write(
            to: directory.appendingPathComponent("theme.json"), options: .atomic)
    }
}
