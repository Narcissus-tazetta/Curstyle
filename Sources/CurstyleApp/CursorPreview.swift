import CursorKit
import SwiftUI

/// フレームの切り出しは重くないが、グリッドの再描画のたびにやり直さないよう CursorRep の contentHash で覚える。
@MainActor
final class FrameCache {
    static let shared = FrameCache()
    private var frames: [String: (frames: [CGImage], scale: Int)] = [:]

    func frames(for rep: CursorRep) -> (frames: [CGImage], scale: Int) {
        let key = rep.contentHash
        if let hit = frames[key] { return hit }
        let made = rep.previewFrames()
        frames[key] = made
        return made
    }
}

/// カーソル1つを、登録形式どおりの間隔でアニメさせて描く。「視差効果を減らす」では先頭フレームで止める。
struct CursorPreview: View {
    let rep: CursorRep
    /// 1pt を何倍で描くか。
    var zoom: CGFloat = 1
    var showsHotspot = false
    var animates = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let (frames, scale) = FrameCache.shared.frames(for: rep)
        let size = CGSize(width: rep.size.width * zoom, height: rep.size.height * zoom)
        Group {
            if frames.count > 1, animates, !reduceMotion, rep.frameDuration > 0 {
                TimelineView(.periodic(from: .now, by: rep.frameDuration)) { context in
                    let index =
                        Int(context.date.timeIntervalSinceReferenceDate / rep.frameDuration) % frames.count
                    frame(frames[index], scale: scale)
                }
            } else if let first = frames.first {
                frame(first, scale: scale)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) {
            if showsHotspot {
                HotspotMarker()
                    .offset(x: rep.hotspot.x * zoom - 6, y: rep.hotspot.y * zoom - 6)
                    .transition(.opacity)
            }
        }
        .accessibilityHidden(true)
    }

    /// 画像の画素より大きく描くとき(1x 画像の拡大)はぼかさず、画素の並びをそのまま見せる。
    private func frame(_ image: CGImage, scale: Int) -> some View {
        Image(decorative: image, scale: CGFloat(scale))
            .resizable()
            .interpolation(zoom > CGFloat(scale) ? .none : .high)
    }
}

private struct HotspotMarker: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.red, lineWidth: 1.5)
            Rectangle().fill(Color.red).frame(width: 1.5, height: 12)
            Rectangle().fill(Color.red).frame(width: 12, height: 1.5)
        }
        .frame(width: 12, height: 12)
        .shadow(color: .white.opacity(0.8), radius: 0.5)
    }
}
