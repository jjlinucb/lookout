import Foundation

/// The 18 things NudeNet's detector knows, in its output order.
public let nudeNetLabels = [
    "FEMALE_GENITALIA_COVERED", "FACE_FEMALE", "BUTTOCKS_EXPOSED", "FEMALE_BREAST_EXPOSED",
    "FEMALE_GENITALIA_EXPOSED", "MALE_BREAST_EXPOSED", "ANUS_EXPOSED", "FEET_EXPOSED",
    "BELLY_COVERED", "FEET_COVERED", "ARMPITS_COVERED", "ARMPITS_EXPOSED", "FACE_MALE",
    "BELLY_EXPOSED", "MALE_GENITALIA_EXPOSED", "ANUS_COVERED", "FEMALE_BREAST_COVERED",
    "BUTTOCKS_COVERED",
]

/// Turns the model's raw output into hits, the way NudeNet's own
/// `_postprocess` does. The image went in padded to a square at the right
/// and bottom, then shrunk to `modelSize`.
///
/// - Parameters:
///   - output: `[4 + labels][candidates]`, channels first: centre x, centre y,
///     width, height, then one score per label.
///   - candidates: number of candidate boxes (2100 at 320 pixels).
///   - imageWidth, imageHeight: the image's size before padding.
public func decodeDetections(_ output: [Float], candidates n: Int, imageWidth: Int, imageHeight: Int,
                             modelSize: Int = 320, labels: [String] = nudeNetLabels) -> [Hit] {
    let side = Float(max(imageWidth, imageHeight)), scale = side / Float(modelSize)
    let W = Float(imageWidth), H = Float(imageHeight)
    var boxes: [(x: Float, y: Float, w: Float, h: Float)] = [], scores: [Float] = [], ids: [Int] = []
    for i in 0..<n {
        var best: Float = -1, bestID = 0
        for c in 0..<labels.count where output[(4 + c) * n + i] > best {
            best = output[(4 + c) * n + i]; bestID = c
        }
        guard best >= 0.2 else { continue }
        let cw = output[2 * n + i], ch = output[3 * n + i]
        var x = (output[i] - cw / 2) * scale, y = (output[n + i] - ch / 2) * scale
        var w = cw * scale, h = ch * scale
        x = max(0, min(x, W)); y = max(0, min(y, H))
        w = min(w, W - x); h = min(h, H - y)
        boxes.append((x, y, w, h)); scores.append(best); ids.append(bestID)
    }
    return nms(boxes: boxes, scores: scores, scoreThreshold: 0.25, iouThreshold: 0.45).map {
        let b = boxes[$0]
        return Hit(labels[ids[$0]], scores[$0], Box(Int(b.x), Int(b.y), Int(b.w), Int(b.h)))
    }
}

/// Greedy non-maximum suppression across all labels, like OpenCV's NMSBoxes.
func nms(boxes: [(x: Float, y: Float, w: Float, h: Float)], scores: [Float],
         scoreThreshold: Float, iouThreshold: Float) -> [Int] {
    let order = scores.indices.filter { scores[$0] >= scoreThreshold }.sorted { scores[$0] > scores[$1] }
    var kept: [Int] = []
    for i in order {
        let a = boxes[i]
        let clash = kept.contains { j in
            let b = boxes[j]
            let iw = max(0, min(a.x + a.w, b.x + b.w) - max(a.x, b.x))
            let ih = max(0, min(a.y + a.h, b.y + b.h) - max(a.y, b.y))
            let inter = iw * ih, union = a.w * a.h + b.w * b.h - inter
            return union > 0 && inter / union > iouThreshold
        }
        if !clash { kept.append(i) }
    }
    return kept
}
