import CoreGraphics
import Foundation
import ImageIO

extension CursorRep {
    public func withHotspot(_ hotspot: CGPoint) -> CursorRep {
        var rep = self
        rep.hotspot = hotspot
        return rep
    }

    /// 静止画は間隔を持たない(登録形式で 0)ので変えない。
    public func withFrameDuration(_ duration: Double) -> CursorRep {
        guard frameCount > 1 else { return self }
        var rep = self
        rep.frameDuration = duration
        return rep
    }

    /// 大きさを factor 倍にする。画像は最も大きい元画像から作り直す(縮小した画像をもう一度拡大して劣化させない)。
    /// 登録形式は「画像幅が size.width の整数倍」を要求するので、size は整数 pt に丸めてから各画像の倍率を掛ける。
    public func scalingSize(by factor: Double) throws -> CursorRep {
        let newSize = CGSize(
            width: max(1, (size.width * factor).rounded()), height: max(1, (size.height * factor).rounded()))
        guard let largest = images.max(by: { $0.width < $1.width }) else {
            throw CursorKitError.invalidCursor(L10n.text("画像が無い"))
        }
        let pixelScales = images.map { Double($0.width) / size.width }
        var rep = self
        rep.size = newSize
        rep.images = try zip(images, pixelScales).map { _, scale in
            try resampleStrip(
                largest, frameCount: frameCount,
                to: CGSize(width: newSize.width * scale, height: newSize.height * scale))
        }
        // 0.5pt 刻み(Retina の1画素)にそろえる。
        func snap(_ v: CGFloat, _ ratio: CGFloat, _ upper: CGFloat) -> CGFloat {
            min(max((v * ratio * 2).rounded() / 2, 0), upper)
        }
        rep.hotspot = CGPoint(
            x: snap(hotspot.x, newSize.width / size.width, newSize.width),
            y: snap(hotspot.y, newSize.height / size.height, newSize.height))
        return rep
    }

    /// GIF / PNG などの画像ファイルから作る。長い辺を pointSize pt にそろえ、1x と 2x の画像を作る。
    /// GIF はすべてのコマを読み、PNG などは先頭の1枚だけを使う。ホットスポットは左上(呼び出し側で決める)。
    public static func fromImageFile(_ url: URL, pointSize: Double) throws -> (rep: CursorRep, adjustment: String?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CursorKitError.io(L10n.text("画像を読めない: {0}", String(describing: url.lastPathComponent)))
        }
        let isGIF = (CGImageSourceGetType(source) as String?) == "com.compuserve.gif"
        let count = isGIF ? CGImageSourceGetCount(source) : min(CGImageSourceGetCount(source), 1)
        var frames: [CGImage] = []
        var delays: [Int] = []  // 1/100 秒単位(GIF の格納単位)
        for i in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                throw CursorKitError.io(
                    L10n.text("{0} のコマ {1} を読めない", String(describing: url.lastPathComponent), String(describing: i)))
            }
            frames.append(image)
            if isGIF { delays.append(gifDelay(source, i)) }
        }
        guard let first = frames.first else {
            throw CursorKitError.io(L10n.text("{0} に画像が無い", String(describing: url.lastPathComponent)))
        }
        guard frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            throw CursorKitError.invalidCursor(L10n.text("コマごとに画像の大きさが違う"))
        }

        // 登録形式は全コマ同じ間隔なので、間隔が違えば最大公約数で割ってコマを繰り返す(.ani と同じ)。
        var sequence = frames
        var duration = 0.0
        if frames.count > 1 {
            let unit = delays.reduce(0) { gcd($0, $1) }
            sequence = zip(frames, delays).flatMap { Array(repeating: $0, count: $1 / unit) }
            duration = Double(unit) / 100
        }

        let longer = Double(max(first.width, first.height))
        let size = CGSize(
            width: max(1, (Double(first.width) * pointSize / longer).rounded()),
            height: max(1, (Double(first.height) * pointSize / longer).rounded()))
        let strip = try WindowsCursorImporter.stack(sequence.map(normalizedImage))
        let images = try [1, 2].map {
            try resampleStrip(
                strip, frameCount: sequence.count,
                to: CGSize(width: size.width * Double($0), height: size.height * Double($0)))
        }
        return try CursorRep(
            size: size, hotspot: .zero, frameCount: sequence.count, frameDuration: duration, images: images
        ).importingAnimation()
    }

    /// ブラウザと同じく、0.02 秒未満の指定は 0.1 秒として扱う(作者がブラウザで見た速さに合わせる)。
    private static func gifDelay(_ source: CGImageSource, _ index: Int) -> Int {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let seconds =
            (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0
        let hundredths = Int((seconds * 100).rounded())
        return hundredths < 2 ? 10 : hundredths
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

extension CursorTheme {
    /// すべてのカーソルの大きさを factor 倍にする。同じ画像を共有するキーは同じ結果になるよう、1回だけ作って使い回す。
    public func scalingSize(by factor: Double) throws -> CursorTheme {
        var theme = self
        var cache: [String: CursorRep] = [:]
        for (key, rep) in cursors {
            let hash = rep.contentHash
            if cache[hash] == nil { cache[hash] = try rep.scalingSize(by: factor) }
            theme.cursors[key] = cache[hash]
        }
        return theme
    }

    /// アニメの速さを factor 倍にする(2 なら1コマの時間が半分)。静止画は変えない。
    public func scalingAnimationSpeed(by factor: Double) -> CursorTheme {
        var theme = self
        theme.cursors = cursors.mapValues { $0.withFrameDuration($0.frameDuration / factor) }
        return theme
    }
}
