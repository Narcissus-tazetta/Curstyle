import Foundation

struct AnimationTimeline {
    let indices: [Int]
    let frameDuration: Double
    let adjustment: String?

    init(durations: [Int], ticksPerSecond: Double) {
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let unit = durations.reduce(0, gcd)
        let repeats = durations.map { $0 / unit }
        let total = repeats.reduce(0, +)
        let count = min(total, CursorRep.maxAnimationFrames)
        var sourceIndex = 0
        var boundary = repeats[0]
        // 繰り返し画像を作ってから間引くと、表示時間だけで巨大な中間画像ができる。
        // 仮想的に展開したコマ番号を使い、従来の間引きと同じ位置だけを選ぶ。
        indices = (0..<count).map { i in
            let position = (total / count) * i + (total % count) * i / count
            while position >= boundary {
                sourceIndex += 1
                boundary += repeats[sourceIndex]
            }
            return sourceIndex
        }
        frameDuration =
            total == count
            ? Double(unit) / ticksPerSecond
            : Double(unit) / ticksPerSecond * Double(total) / Double(count)
        adjustment = CursorRep.animationAdjustment(originalFrameCount: total)
    }
}
