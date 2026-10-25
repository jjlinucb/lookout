import Foundation

/// A coarse sample of a screen: one RGB value every `step` pixels. Only this
/// is kept between looks, in memory, to see what changed.
public struct Grid: Equatable {
    public let width, height, step: Int
    public let pixels: [UInt8]  // width * height * 3, row by row

    public init(width: Int, height: Int, step: Int, pixels: [UInt8]) {
        (self.width, self.height, self.step, self.pixels) = (width, height, step, pixels)
    }

    /// Sample a 32-bit BGRA image (the screen capture format).
    public static func sample(bgra: UnsafeRawPointer, bytesPerRow: Int, width: Int, height: Int, step: Int) -> Grid {
        let gw = (width + step - 1) / step, gh = (height + step - 1) / step
        var out = [UInt8](repeating: 0, count: gw * gh * 3)
        let p = bgra.assumingMemoryBound(to: UInt8.self)
        var i = 0
        for gy in 0..<gh {
            let row = p + gy * step * bytesPerRow
            for gx in 0..<gw {
                let px = row + gx * step * 4
                out[i] = px[0]; out[i + 1] = px[1]; out[i + 2] = px[2]
                i += 3
            }
        }
        return Grid(width: gw, height: gh, step: step, pixels: out)
    }
}

/// Rechecks only what changed since the last look, per display. A still
/// screen costs nothing; a change smaller than a thumbnail (the cursor, a
/// clock) is ignored; a small change (a pop-up, an image loading) is checked
/// up close, which also helps the model, since it shrinks every image to 320
/// pixels. Hits on unchanged parts are kept, so a still image keeps counting
/// toward "two frames in a row".
public struct ChangeTracker {
    public static let step = 24
    /// A pixel moved when any color channel changed by more than this.
    public static let moveThreshold = 24
    /// Changes smaller than this many pixels across are ignored.
    public static let minChange = 64
    /// Changes covering this share of the screen get a full look.
    public static let fullShare = 0.4

    var last: [Int: Grid] = [:]
    var seen: [Int: [Hit]] = [:]

    public init() {}

    public mutating func forget() { last = [:]; seen = [:] }

    /// `scan(nil)` checks the whole frame; `scan(box)` checks that part and
    /// returns hits relative to the part's top left.
    public mutating func look(display: Int, grid: Grid, frameWidth w: Int, frameHeight h: Int,
                              scan: (Box?) -> [Hit]) -> [Hit] {
        let step = grid.step
        let previous = last[display]
        last[display] = grid
        guard let previous, previous.width == grid.width, previous.height == grid.height else {
            seen[display] = scan(nil)
            return seen[display]!
        }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        let a = grid.pixels, b = previous.pixels
        for gy in 0..<grid.height {
            for gx in 0..<grid.width {
                let i = (gy * grid.width + gx) * 3
                if abs(Int(a[i]) - Int(b[i])) > Self.moveThreshold
                    || abs(Int(a[i + 1]) - Int(b[i + 1])) > Self.moveThreshold
                    || abs(Int(a[i + 2]) - Int(b[i + 2])) > Self.moveThreshold {
                    minX = min(minX, gx); maxX = max(maxX, gx)
                    minY = min(minY, gy); maxY = max(maxY, gy)
                }
            }
        }
        if maxX < 0 { return seen[display] ?? [] }
        let y0 = max(0, (minY - 1) * step), y1 = min(h, (maxY + 2) * step)
        let x0 = max(0, (minX - 1) * step), x1 = min(w, (maxX + 2) * step)
        if min(y1 - y0, x1 - x0) < Self.minChange + 2 * step { return seen[display] ?? [] }
        if Double((y1 - y0) * (x1 - x0)) >= Self.fullShare * Double(h * w) {
            seen[display] = scan(nil)
            return seen[display]!
        }
        let region = Box(x0, y0, x1 - x0, y1 - y0)
        let fresh = scan(region).map { Hit($0.label, $0.score, Box($0.box.x + x0, $0.box.y + y0, $0.box.w, $0.box.h)) }
        let kept = (seen[display] ?? []).filter { !$0.box.overlaps(region) }
        seen[display] = kept + fresh
        return seen[display]!
    }
}
