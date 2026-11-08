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
        guard !cursors.isEmpty else { throw CursorKitError.theme("カーソルが1つも無い") }
        var plan: [String: (key: String, rep: CursorRep)] = [:]
        for (key, rep) in cursors.sorted(by: { $0.key < $1.key }) {
            do {
                try rep.validate()
            } catch {
                throw CursorKitError.theme("\(key): \(error)")
            }
            for target in try CursorCatalog.targets(for: key) {
                if let other = plan[target] {
                    throw CursorKitError.theme("\(key) と \(other.key) が同じ \(target) を指している")
                }
                plan[target] = (key, rep)
            }
        }
        return plan.keys.sorted().map { ($0, plan[$0]!.rep) }
    }

    /// テーマディレクトリ: theme.json と PNG。
    /// ```
    /// { "name": "...", "cursors": { "arrow": { "size": [w, h], "hotspot": [x, y],
    ///   "frameCount": 1, "frameDuration": 0, "images": ["arrow@1x.png", "arrow@2x.png"] } } }
    /// ```
    public static func load(directory: URL) throws -> CursorTheme {
        struct Entry: Decodable {
            var size: [Double]
            var hotspot: [Double]
            var frameCount: Int?
            var frameDuration: Double?
            var images: [String]
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
            throw CursorKitError.theme("\(jsonURL.path) を読めない: \(error)")
        }
        var cursors: [String: CursorRep] = [:]
        for (key, e) in file.cursors {
            guard e.size.count == 2, e.hotspot.count == 2 else {
                throw CursorKitError.theme("\(key): size と hotspot は [x, y] の2要素")
            }
            let images = try e.images.map { try readPNG(at: directory.appendingPathComponent($0)) }
            cursors[key] = CursorRep(
                size: CGSize(width: e.size[0], height: e.size[1]), hotspot: CGPoint(x: e.hotspot[0], y: e.hotspot[1]),
                frameCount: e.frameCount ?? 1, frameDuration: e.frameDuration ?? 0, images: images)
        }
        return CursorTheme(name: file.name, cursors: cursors)
    }
}
