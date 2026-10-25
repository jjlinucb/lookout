import Testing
@testable import LookoutCore

/// A fake 1600 x 900 BGRA screen, grey, with optional black rectangles.
struct Screen {
    let w = 1600, h = 900
    var px: [UInt8]
    init() { px = [UInt8](repeating: 200, count: 1600 * 900 * 4) }

    mutating func black(x: Range<Int>, y: Range<Int>) {
        for yy in y { for xx in x { let i = (yy * w + xx) * 4; px[i] = 0; px[i + 1] = 0; px[i + 2] = 0 } }
    }

    var grid: Grid {
        px.withUnsafeBytes { Grid.sample(bgra: $0.baseAddress!, bytesPerRow: w * 4, width: w, height: h, step: ChangeTracker.step) }
    }

    func has(black region: Box?) -> Bool {
        let r = region ?? Box(0, 0, w, h)
        for yy in r.y..<(r.y + r.h) { for xx in r.x..<(r.x + r.w) where px[(yy * w + xx) * 4] == 0 { return true } }
        return false
    }
}

@Suite struct ChangeTrackerTests {
    var t = ChangeTracker()
    var scans: [Box?] = []

    /// Look once; the fake detector sees "revealing" wherever there's black.
    mutating func look(_ s: Screen) -> [Hit] {
        var calls: [Box?] = []
        let hits = t.look(display: 0, grid: s.grid, frameWidth: s.w, frameHeight: s.h) { region in
            calls.append(region)
            return s.has(black: region) ? [Hit("BUTTOCKS_COVERED", 0.7, Box(10, 10, 50, 50))] : []
        }
        scans += calls
        return hits
    }

    @Test mutating func stillScreenIsNotRechecked() {
        _ = look(Screen()); _ = look(Screen())
        #expect(scans.count == 1)
    }

    @Test mutating func tinyChangeIsIgnored() {
        _ = look(Screen())
        var cursor = Screen()
        cursor.black(x: 700..<702, y: 400..<420)
        _ = look(cursor)
        #expect(scans.count == 1)
    }

    @Test mutating func smallChangeIsCheckedUpCloseAndPlacedOnScreen() throws {
        _ = look(Screen())
        var popup = Screen()
        popup.black(x: 600..<900, y: 300..<500)
        let hits = look(popup)
        let region = try #require(scans.last ?? nil)
        #expect((200...260).contains(region.h) && (300...360).contains(region.w))
        #expect(hits.first!.box.x > 500)
    }

    @Test mutating func stillRevealingImageCountsTwoFramesInARow() {
        var popup = Screen()
        popup.black(x: 600..<900, y: 300..<500)
        _ = look(Screen())
        var j = Judge(Settings())
        #expect(j.judge(look(popup)) == nil)
        #expect(j.judge(look(popup))?.0 == .revealing)
    }

    @Test mutating func imageGoneClearsItsHit() {
        var popup = Screen()
        popup.black(x: 600..<900, y: 300..<500)
        _ = look(Screen()); _ = look(popup)
        #expect(look(Screen()).isEmpty)
    }

    @Test mutating func bigChangeChecksTheWholeScreen() {
        _ = look(Screen())
        var dark = Screen()
        dark.black(x: 0..<1600, y: 0..<900)
        _ = look(dark)
        #expect(scans.count == 2 && scans.last! == nil)
    }

    @Test mutating func newDisplaySizeChecksTheWholeScreen() {
        _ = look(Screen())
        let other = Grid(width: 10, height: 10, step: 24, pixels: [UInt8](repeating: 0, count: 300))
        var full = false
        _ = t.look(display: 0, grid: other, frameWidth: 240, frameHeight: 240) { full = $0 == nil; return [] }
        #expect(full)
    }
}

@Suite struct DecodeTests {
    /// Two overlapping candidates for one label and one weak candidate.
    @Test func decodesScalesAndSuppressesOverlaps() {
        let n = 3, labels = nudeNetLabels.count
        var out = [Float](repeating: 0, count: (4 + labels) * n)
        func put(_ i: Int, cx: Float, cy: Float, w: Float, h: Float, label: Int, score: Float) {
            out[i] = cx; out[n + i] = cy; out[2 * n + i] = w; out[3 * n + i] = h
            out[(4 + label) * n + i] = score
        }
        put(0, cx: 100, cy: 100, w: 40, h: 40, label: 3, score: 0.9)   // FEMALE_BREAST_EXPOSED
        put(1, cx: 102, cy: 101, w: 40, h: 40, label: 3, score: 0.6)   // same spot, weaker
        put(2, cx: 200, cy: 50, w: 20, h: 20, label: 1, score: 0.1)    // below 0.2
        // A 1600 x 900 image was padded to 1600 x 1600 and shrunk to 320: scale 5.
        let hits = decodeDetections(out, candidates: n, imageWidth: 1600, imageHeight: 900)
        #expect(hits.count == 1)
        #expect(hits[0].label == "FEMALE_BREAST_EXPOSED")
        #expect(hits[0].box == Box(400, 400, 200, 200))
    }

    @Test func boxesAreClippedToTheImage() {
        let n = 1
        var out = [Float](repeating: 0, count: (4 + nudeNetLabels.count) * n)
        out[0] = 310; out[1] = 10; out[2] = 40; out[3] = 40; out[4 + 2] = 0.8
        let hits = decodeDetections(out, candidates: n, imageWidth: 320, imageHeight: 100)
        #expect(hits[0].box == Box(290, 0, 30, 40))  // like NudeNet: the top is clipped, the height is not shrunk
    }
}
