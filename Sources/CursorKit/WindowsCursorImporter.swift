import CoreGraphics
import Foundation
import ImageIO

/// Windows のカーソルテーマ(.ani / .cur を役割名のファイルで並べたフォルダ)を CursorTheme に変換する。
public enum WindowsCursorImporter {
    /// ファイル名(拡張子なし・小文字)→ 当てる Curstyle のキー。
    /// macOS 側の対応物が無い役割(Busy / Alternate / Handwriting / Pin / Person)は含めず、標準のまま残す。
    /// Busy(Wait)は WindowServer が自前で描くスピナーで、カーソル画像の差し替え対象かどうか未確認。
    /// 役割名と番号の対応は目視では未確認(CursorCatalog.roleNames と同じ)。
    public static let roleMap: [String: [String]] = [
        "normal": ["arrow"],
        "text": ["ibeam"],
        "link": ["pointingHand"],
        "help": ["Help"],
        "working": ["BusyButClickable"],
        "unavailable": ["NotAllowed"],
        "precision": ["Cross"],
        "move": ["WindowMove"],
        "horizontal": [
            "ResizeLeftRight", "ResizeLeft", "ResizeRight", "WindowResizeEastWest", "WindowResizeEast",
            "WindowResizeWest",
        ],
        "vertical": [
            "ResizeUpDown", "ResizeUp", "ResizeDown", "WindowResizeNorthSouth", "WindowResizeNorth",
            "WindowResizeSouth",
        ],
        "diagonal1": ["WindowResizeNorthWestSouthEast", "WindowResizeNorthWest", "WindowResizeSouthEast"],
        "diagonal2": ["WindowResizeNorthEastSouthWest", "WindowResizeNorthEast", "WindowResizeSouthWest"],
    ]

    public struct Result {
        public var theme: CursorTheme
        public var skippedFiles: [String]
    }

    /// pixelsPerPoint: 画像1枚の何ピクセルを1ptとみなすか。Windows の 32px を Retina で 32px のまま見せるなら 2。
    public static func importTheme(directory: URL, name: String, pixelsPerPoint: Int) throws -> Result {
        guard (1...4).contains(pixelsPerPoint) else { throw CursorKitError.theme("--scale は 1〜4") }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var cursors: [String: CursorRep] = [:]
        var skipped: [String] = []
        // 同じ役割に .ani と .cur があれば .ani(アニメ)を優先する。
        for file in files.sorted(by: { $0.pathExtension.lowercased() > $1.pathExtension.lowercased() }) {
            let ext = file.pathExtension.lowercased()
            guard ext == "ani" || ext == "cur" else { continue }
            let stem = file.deletingPathExtension().lastPathComponent.lowercased()
            guard let keys = roleMap[stem] else {
                skipped.append(file.lastPathComponent)
                continue
            }
            guard keys.allSatisfy({ cursors[$0] == nil }) else { continue }
            let rep: CursorRep
            do {
                rep = try cursorRep(
                    from: Data(contentsOf: file), isAnimated: ext == "ani", pixelsPerPoint: pixelsPerPoint)
            } catch {
                throw CursorKitError.theme("\(file.lastPathComponent): \(error)")
            }
            for key in keys { cursors[key] = rep }
        }
        guard !cursors.isEmpty else { throw CursorKitError.theme("\(directory.path) に取り込める .ani / .cur が無い") }
        return Result(theme: CursorTheme(name: name, cursors: cursors), skippedFiles: skipped)
    }

    // MARK: - 解析

    struct Frame {
        var image: CGImage
        var hotspot: CGPoint
    }

    static func cursorRep(from data: Data, isAnimated: Bool, pixelsPerPoint: Int) throws -> CursorRep {
        let frames: [Frame]
        var durations: [Int]  // 1/60 秒単位。フレームごと
        if isAnimated {
            (frames, durations) = try parseANI(data)
        } else {
            frames = [try parseCUR(data)]
            durations = [0]
        }
        guard let first = frames.first else { throw CursorKitError.invalidCursor("フレームが無い") }
        let width = first.image.width
        let height = first.image.height
        guard frames.allSatisfy({ $0.image.width == width && $0.image.height == height }) else {
            throw CursorKitError.invalidCursor("フレームごとに画像の大きさが違う")
        }
        guard width % pixelsPerPoint == 0, height % pixelsPerPoint == 0 else {
            throw CursorKitError.invalidCursor("画像 \(width)x\(height) が --scale \(pixelsPerPoint) で割り切れない")
        }

        // 登録形式は全フレーム同じ間隔なので、間隔が違うなら最小公約数で割ってフレームを繰り返す。
        var sequence = frames
        var duration = 0.0
        if frames.count > 1 {
            let unit = durations.reduce(0) { gcd($0, $1) }
            guard unit > 0 else { throw CursorKitError.invalidCursor("フレームの表示時間が 0") }
            sequence = zip(frames, durations).flatMap { Array(repeating: $0, count: $1 / unit) }
            duration = Double(unit) / 60
        }

        return CursorRep(
            size: CGSize(width: width / pixelsPerPoint, height: height / pixelsPerPoint),
            hotspot: CGPoint(x: first.hotspot.x / Double(pixelsPerPoint), y: first.hotspot.y / Double(pixelsPerPoint)),
            frameCount: sequence.count, frameDuration: duration, images: [try stack(sequence.map(\.image))])
    }

    /// RIFF 'ACON'。anih(ヘッダー)・rate(ステップごとの 1/60 秒)・seq(ステップ→フレーム番号)・LIST fram の icon。
    static func parseANI(_ data: Data) throws -> (frames: [Frame], durations: [Int]) {
        guard data.count >= 12, data[0..<4].elementsEqual("RIFF".utf8), data[8..<12].elementsEqual("ACON".utf8) else {
            throw CursorKitError.invalidCursor("ANI ではない(RIFF ACON でない)")
        }
        var header: (steps: Int, jiffies: Int)?
        var rate: [Int]?
        var seq: [Int]?
        var icons: [Data] = []

        func walk(_ start: Int, _ end: Int) throws {
            var pos = start
            while pos + 8 <= end {
                let id = String(decoding: data[pos..<pos + 4], as: UTF8.self)
                let size = Int(data.le32(pos + 4))
                let body = pos + 8
                guard body + size <= data.count else { throw CursorKitError.invalidCursor("チャンク \(id) がファイルの外に出る") }
                switch id {
                case "LIST" where size >= 4 && String(decoding: data[body..<body + 4], as: UTF8.self) == "fram":
                    try walk(body + 4, body + size)
                case "anih":
                    guard size >= 36 else { throw CursorKitError.invalidCursor("anih が短い") }
                    guard data.le32(body + 32) & 1 != 0 else {
                        throw CursorKitError.invalidCursor("フレームが生の画像データ形式(未対応。icon 形式のみ)")
                    }
                    header = (Int(data.le32(body + 8)), Int(data.le32(body + 28)))
                case "rate":
                    rate = (0..<size / 4).map { Int(data.le32(body + $0 * 4)) }
                case "seq ":
                    seq = (0..<size / 4).map { Int(data.le32(body + $0 * 4)) }
                case "icon":
                    icons.append(data.subdata(in: body..<body + size))
                default:
                    break
                }
                pos = body + size + (size & 1)
            }
        }
        try walk(12, data.count)

        guard let header else { throw CursorKitError.invalidCursor("anih が無い") }
        let decoded = try icons.map(parseCUR)
        let order = seq ?? Array(0..<header.steps)
        guard order.count == header.steps, order.allSatisfy({ decoded.indices.contains($0) }) else {
            throw CursorKitError.invalidCursor("ステップ数 \(header.steps) とフレーム数 \(decoded.count) が合わない")
        }
        let durations = (0..<header.steps).map { rate?[$0] ?? header.jiffies }
        guard durations.allSatisfy({ $0 > 0 }) else { throw CursorKitError.invalidCursor("表示時間が 0 のステップがある") }
        return (order.map { decoded[$0] }, durations)
    }

    /// ICONDIR(type 2 = cursor)。大きい方の画像を取り、hotspot はディレクトリエントリの planes / bitCount 欄から読む。
    static func parseCUR(_ data: Data) throws -> Frame {
        guard data.count >= 22, data.le16(0) == 0, data.le16(2) == 2 else {
            throw CursorKitError.invalidCursor("CUR ではない(ICONDIR の type が 2 でない)")
        }
        let count = Int(data.le16(4))
        guard count >= 1, 6 + count * 16 <= data.count else { throw CursorKitError.invalidCursor("CUR のエントリが壊れている") }
        // 幅 0 は 256 を表す。
        let best = (0..<count).max { entryWidth(data, $0) < entryWidth(data, $1) }!
        let entry = 6 + best * 16
        let hotspot = CGPoint(x: Int(data.le16(entry + 4)), y: Int(data.le16(entry + 6)))

        // ImageIO は .cur の単独ファイルを ICO として読めるので、選んだエントリだけの CUR に作り直して渡す。
        let size = Int(data.le32(entry + 8))
        let offset = Int(data.le32(entry + 12))
        guard offset + size <= data.count else { throw CursorKitError.invalidCursor("CUR の画像データがファイルの外に出る") }
        var single = Data(data[0..<6])
        single.replaceSubrange(4..<6, with: [1, 0])
        var dir = Data(data[entry..<entry + 16])
        dir.replaceSubrange(12..<16, with: UInt32(22).leBytes)
        single += dir
        single += data[offset..<offset + size]

        guard let source = CGImageSourceCreateWithData(single as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw CursorKitError.invalidCursor("CUR の画像を ImageIO で読めない") }
        return Frame(image: normalizedImage(image), hotspot: hotspot)
    }

    private static func entryWidth(_ data: Data, _ index: Int) -> Int {
        let w = Int(data[6 + index * 16])
        return w == 0 ? 256 : w
    }

    /// 先頭フレームが上。
    static func stack(_ images: [CGImage]) throws -> CGImage {
        let w = images[0].width
        let h = images[0].height
        guard
            let ctx = CGContext(
                data: nil, width: w, height: h * images.count, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CursorKitError.io("フレームを並べる画像を作れない") }
        for (i, image) in images.enumerated() {
            ctx.draw(image, in: CGRect(x: 0, y: (images.count - 1 - i) * h, width: w, height: h))
        }
        return ctx.makeImage()!
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

extension Data {
    fileprivate func le16(_ offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    fileprivate func le32(_ offset: Int) -> UInt32 {
        UInt32(le16(offset)) | UInt32(le16(offset + 2)) << 16
    }
}

extension UInt32 {
    fileprivate var leBytes: [UInt8] { (0..<4).map { UInt8((self >> ($0 * 8)) & 0xff) } }
}
