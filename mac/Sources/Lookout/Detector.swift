import CoreML
import CoreVideo
import Foundation
import LookoutCore

/// NudeNet's 320n detector, converted to Core ML, on the Neural Engine when
/// the Mac has one. Images go in as they do in NudeNet: padded to a square at
/// the right and bottom with black, then shrunk to 320 x 320.
final class Detector {
    static let size = 320
    let model: MLModel
    private var input: CVPixelBuffer

    /// Loads the compiled model, compiling the bundled .mlpackage once and
    /// keeping the result in `cache` (the build compiles it when it can).
    init(bundled: URL, cache: URL) throws {
        let compiled: URL
        if bundled.pathExtension == "mlmodelc" {
            compiled = bundled
        } else {
            let stamp = (try? FileManager.default.attributesOfItem(atPath: bundled.path)[.modificationDate] as? Date)
                .map { Int($0.timeIntervalSince1970) } ?? 0
            compiled = cache.appendingPathComponent("NudeNet320n-\(stamp).mlmodelc")
            if !FileManager.default.fileExists(atPath: compiled.path) {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                let tmp = try MLModel.compileModel(at: bundled)
                try? FileManager.default.removeItem(at: compiled)
                try FileManager.default.moveItem(at: tmp, to: compiled)
            }
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: compiled, configuration: config)
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, Self.size, Self.size, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
        guard let pb else { throw NSError(domain: "Lookout", code: 1) }
        input = pb
    }

    /// Check part of a BGRA frame (all of it when `region` is nil). Hits come
    /// back relative to the region's top left.
    func scan(_ frame: CVPixelBuffer, region: Box?) -> [Hit] {
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        CVPixelBufferLockBaseAddress(input, [])
        defer {
            CVPixelBufferUnlockBaseAddress(input, [])
            CVPixelBufferUnlockBaseAddress(frame, .readOnly)
        }
        let r = region ?? Box(0, 0, CVPixelBufferGetWidth(frame), CVPixelBufferGetHeight(frame))
        guard r.w > 0, r.h > 0, let src = CVPixelBufferGetBaseAddress(frame),
              let dst = CVPixelBufferGetBaseAddress(input) else { return [] }
        let srcRow = CVPixelBufferGetBytesPerRow(frame), dstRow = CVPixelBufferGetBytesPerRow(input)

        // Pad to a black square at the right and bottom, then shrink to 320 with
        // bilinear sampling, the same way NudeNet does it through OpenCV
        // (cv2.copyMakeBorder, then cv2.resize INTER_LINEAR), so its scores
        // and the thresholds tuned on them carry over. NudeNet's loader also
        // swaps red and blue (cvtColor RGBA2BGR on a 3-channel image), so the
        // model has always seen blue in its red slot; the swap is copied here.
        let side = max(r.w, r.h), scale = Float(side) / Float(Self.size)
        let s = src.assumingMemoryBound(to: UInt8.self) + r.y * srcRow + r.x * 4
        let d = dst.assumingMemoryBound(to: UInt8.self)
        func axis(_ i: Int, _ limit: Int) -> (Int, Int, Float) {
            let f = max(0, (Float(i) + 0.5) * scale - 0.5)
            let i0 = min(Int(f), side - 1), i1 = min(i0 + 1, side - 1)
            return (i0, i1, f - Float(i0))
        }
        let xs = (0..<Self.size).map { axis($0, r.w) }, ys = (0..<Self.size).map { axis($0, r.h) }
        for oy in 0..<Self.size {
            let (y0, y1, wy) = ys[oy]
            let row = d + oy * dstRow
            for ox in 0..<Self.size {
                let (x0, x1, wx) = xs[ox]
                for c in 0..<3 {
                    // Outside the region is the black padding.
                    func px(_ x: Int, _ y: Int) -> Float { x < r.w && y < r.h ? Float(s[y * srcRow + x * 4 + c]) : 0 }
                    let top = px(x0, y0) * (1 - wx) + px(x1, y0) * wx
                    let bottom = px(x0, y1) * (1 - wx) + px(x1, y1) * wx
                    row[ox * 4 + 2 - c] = UInt8(min(255, (top * (1 - wy) + bottom * wy).rounded()))
                }
                row[ox * 4 + 3] = 255
            }
        }

        guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": input])),
              let arr = out.featureValue(for: "detections")?.multiArrayValue else { return [] }
        let n = arr.shape[2].intValue
        return decodeDetections(Self.floats(arr), candidates: n, imageWidth: r.w, imageHeight: r.h)
    }

    /// The [1, 22, n] output as plain floats, channels first.
    static func floats(_ arr: MLMultiArray) -> [Float] {
        let c = arr.shape[1].intValue, n = arr.shape[2].intValue
        let sc = arr.strides[1].intValue, sn = arr.strides[2].intValue
        var out = [Float](repeating: 0, count: c * n)
        // withUnsafeBufferPointer(ofType: Float16.self) needs macOS 15; the raw pointer works on 14.
        switch arr.dataType {
        case .float16:
            let p = arr.dataPointer.assumingMemoryBound(to: Float16.self)
            for k in 0..<c { for i in 0..<n { out[k * n + i] = Float(p[k * sc + i * sn]) } }
        case .float32:
            let p = arr.dataPointer.assumingMemoryBound(to: Float.self)
            for k in 0..<c { for i in 0..<n { out[k * n + i] = p[k * sc + i * sn] } }
        default:
            for k in 0..<c { for i in 0..<n { out[k * n + i] = arr[[0, k, i] as [NSNumber]].floatValue } }
        }
        return out
    }
}
