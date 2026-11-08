import CoreGraphics
import CursorKit
import Foundation

/// 目視確認用のテーマ。標準カーソルと一目で区別できる形と色にしてある。
/// animated のときは各フレームで色相を回し、アニメが動いているかを見分けられるようにする。
enum TestTheme {
    static let keys = ["arrow", "ibeam", "link"]

    static func make(keys: [String], animated: Bool) throws -> CursorTheme {
        var cursors: [String: CursorRep] = [:]
        for key in keys {
            cursors[key] = try rep(for: key, animated: animated)
        }
        return CursorTheme(name: animated ? "test-animated" : "test", cursors: cursors)
    }

    private static func rep(for key: String, animated: Bool) throws -> CursorRep {
        let frames = animated ? 8 : 1
        let size: CGSize
        let hotspot: CGPoint
        let draw: (CGContext, CGFloat, CGColor) -> Void
        switch key {
        case "arrow":
            size = CGSize(width: 32, height: 32)
            hotspot = CGPoint(x: 2, y: 2)
            draw = { ctx, p, color in
                // CGContext は左下原点。hotspot (2,2) = 左上に先端を置く。
                ctx.move(to: CGPoint(x: 2, y: p - 2))
                ctx.addLine(to: CGPoint(x: p * 0.75, y: p * 0.45))
                ctx.addLine(to: CGPoint(x: 2, y: p * 0.2))
                ctx.closePath()
                fillStroke(ctx, color)
            }
        case "ibeam":
            size = CGSize(width: 16, height: 28)
            hotspot = CGPoint(x: 8, y: 14)
            draw = { ctx, _, color in
                ctx.addRect(CGRect(x: 6, y: 3, width: 4, height: 22))
                ctx.addRect(CGRect(x: 2, y: 23, width: 12, height: 3))
                ctx.addRect(CGRect(x: 2, y: 2, width: 12, height: 3))
                fillStroke(ctx, color)
            }
        case "link":
            size = CGSize(width: 28, height: 28)
            hotspot = CGPoint(x: 14, y: 14)
            draw = { ctx, _, color in
                ctx.addEllipse(in: CGRect(x: 3, y: 3, width: 22, height: 22))
                fillStroke(ctx, color)
                ctx.addEllipse(in: CGRect(x: 11, y: 11, width: 6, height: 6))
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                ctx.fillPath()
            }
        default:
            throw CursorKitError.unknownCursorKey("テスト画像が無い: \(key)(\(keys.joined(separator: "/")) のみ)")
        }
        let baseHue: CGFloat = ["arrow": 0.0, "ibeam": 0.6, "link": 0.33][key]!
        let images = [1, 2].map { scale in
            let w = Int(size.width) * scale
            let h = Int(size.height) * scale
            let ctx = CGContext(
                data: nil, width: w, height: h * frames, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            for f in 0..<frames {
                ctx.saveGState()
                // フレーム 0 が画像の一番上。CGContext は左下原点なので下から積む。
                ctx.translateBy(x: 0, y: CGFloat((frames - 1 - f) * h))
                ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                let hue = (baseHue + CGFloat(f) / CGFloat(frames)).truncatingRemainder(dividingBy: 1)
                draw(ctx, size.width, hsb(hue))
                ctx.restoreGState()
            }
            return ctx.makeImage()!
        }
        return CursorRep(
            size: size, hotspot: hotspot, frameCount: frames, frameDuration: animated ? 0.1 : 0, images: images)
    }

    private static func fillStroke(_ ctx: CGContext, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.setLineWidth(1.5)
        ctx.drawPath(using: .fillStroke)
    }

    private static func hsb(_ h: CGFloat) -> CGColor {
        let i = Int(h * 6) % 6
        let f = h * 6 - CGFloat(Int(h * 6))
        let (r, g, b): (CGFloat, CGFloat, CGFloat) =
            switch i {
            case 0: (1, f, 0)
            case 1: (1 - f, 1, 0)
            case 2: (0, 1, f)
            case 3: (0, 1 - f, 1)
            case 4: (f, 0, 1)
            default: (1, 0, 1 - f)
            }
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
