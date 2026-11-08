import CCursorBridge
import CoreGraphics
import CryptoKit
import Foundation

struct ProbeError: Error, CustomStringConvertible {
    let description: String
}

struct CursorData {
    let size: CGSize
    let hotspot: CGPoint
    let frameCount: Int
    let frameDuration: Double
    let images: [CGImage]

    // 画像は縦に frameCount 枚並んだ1枚のことがあるため、ピクセル全体をハッシュする。
    var pixelHash: String {
        var hasher = SHA256()
        for image in images {
            hasher.update(data: Data("\(image.width)x\(image.height);".utf8))
            hasher.update(data: rgbaBytes(image))
        }
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    var summary: String {
        let dims = images.map { "\($0.width)x\($0.height)" }.joined(separator: ",")
        return String(
            format: "size=%gx%g hot=(%g,%g) frames=%d dur=%.4f images=[%@] hash=%@",
            size.width, size.height, hotspot.x, hotspot.y, frameCount, frameDuration, dims,
            pixelHash)
    }
}

func rgbaBytes(_ image: CGImage) -> Data {
    let width = image.width
    let height = image.height
    var data = Data(count: width * height * 4)
    data.withUnsafeMutableBytes { raw in
        let ctx = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return data
}

func imagesFromArray(_ array: CFArray?) -> [CGImage] {
    guard let array else { return [] }
    return (array as [AnyObject]).map { obj in
        guard CFGetTypeID(obj) == CGImage.typeID else {
            fatalError("画像配列に CGImage 以外が入っている: \(CFCopyTypeIDDescription(CFGetTypeID(obj))!)")
        }
        return obj as! CGImage
    }
}

final class Cursors {
    let sym: CSSymbols
    let cid: CSConnectionID

    init() throws {
        sym = CSResolveSymbols()
        guard let main = sym.mainConnectionID else {
            throw ProbeError(description: "CGSMainConnectionID が見つからない")
        }
        cid = main()
    }

    func require<T>(_ fn: T?, _ name: String) throws -> T {
        guard let fn else { throw ProbeError(description: "\(name) が見つからない") }
        return fn
    }

    func copyRegistered(_ name: String) throws -> (CSError, CursorData?) {
        let fn = try require(sym.copyRegisteredCursorImages, "CGSCopyRegisteredCursorImages")
        var size = CGSize.zero
        var hot = CGPoint.zero
        var frames: UInt = 0
        var dur: CGFloat = 0
        var arr: Unmanaged<CFArray>?
        let err = name.withCString { fn(cid, $0, &size, &hot, &frames, &dur, &arr) }
        guard err == 0 else { return (err, nil) }
        let images = imagesFromArray(arr?.takeRetainedValue())
        return (
            err,
            CursorData(
                size: size, hotspot: hot, frameCount: Int(frames), frameDuration: Double(dur),
                images: images)
        )
    }

    func copyCore(_ id: Int32) throws -> (CSError, CursorData?) {
        let fn = try require(sym.coreCursorCopyImages, "CoreCursorCopyImages")
        var size = CGSize.zero
        var hot = CGPoint.zero
        var frames: UInt = 0
        var dur: CGFloat = 0
        var arr: Unmanaged<CFArray>?
        let err = fn(cid, id, &arr, &size, &hot, &frames, &dur)
        guard err == 0 else { return (err, nil) }
        let images = imagesFromArray(arr?.takeRetainedValue())
        return (
            err,
            CursorData(
                size: size, hotspot: hot, frameCount: Int(frames), frameDuration: Double(dur),
                images: images)
        )
    }

    func register(_ name: String, _ data: CursorData) throws -> (CSError, Int32) {
        let fn = try require(sym.registerCursorWithImages, "CGSRegisterCursorWithImages")
        var seed: Int32 = 0
        let err = name.withCString {
            fn(
                cid, $0, true, true, data.size, data.hotspot, UInt(data.frameCount),
                CGFloat(data.frameDuration), data.images as CFArray, &seed)
        }
        return (err, seed)
    }

    func remove(_ name: String) throws -> CSError {
        let fn = try require(sym.removeRegisteredCursor, "CGSRemoveRegisteredCursor")
        return name.withCString { fn(cid, $0, true) }
    }

    func unregisterAll() throws -> CSError {
        try require(sym.coreCursorUnregisterAll, "CoreCursorUnregisterAll")(cid)
    }

    func cursorScale() throws -> (CSError, Float) {
        var scale: Float = 0
        let err = try require(sym.getCursorScale, "CGSGetCursorScale")(cid, &scale)
        return (err, scale)
    }

    func scanNames(prefix: String, inImageOf symbol: String) -> [String] {
        guard let path = CSImagePathForSymbol(symbol) else { return [] }
        final class Box { var names: [String] = [] }
        let box = Box()
        let ctx = Unmanaged.passUnretained(box).toOpaque()
        _ = CSScanCStrings(
            path, prefix,
            { str, ctx in
                Unmanaged<Box>.fromOpaque(ctx!).takeUnretainedValue().names.append(String(cString: str))
            }, ctx)
        return box.names
    }
}
