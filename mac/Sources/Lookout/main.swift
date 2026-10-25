import AppKit
import CoreML

// Lookout: a menu bar app that checks the screen on this Mac, covers explicit
// images, and keeps a local log. Nothing it sees ever leaves the Mac.

// build_app.sh: `Lookout --compile-model IN.mlpackage OUT.mlmodelc`, since
// the Command Line Tools have no Core ML compiler.
let args = CommandLine.arguments
if args.count == 4, args[1] == "--compile-model" {
    do {
        let out = URL(fileURLWithPath: args[3])
        try? FileManager.default.removeItem(at: out)
        try FileManager.default.moveItem(at: MLModel.compileModel(at: URL(fileURLWithPath: args[2])), to: out)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("compile failed: \(error)\n".utf8))
        exit(1)
    }
}

// `Lookout --scan-image FILE`: run the detector on one picture and print what
// it finds, to check the model without anything on screen.
if args.count == 3, args[1] == "--scan-image" {
    guard let model = Bundle.main.url(forResource: "NudeNet320n", withExtension: "mlmodelc"),
          let detector = try? Detector(bundled: model, cache: FileManager.default.temporaryDirectory),
          let image = NSImage(contentsOfFile: args[2])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let frame = pixelBuffer(from: image) else {
        FileHandle.standardError.write(Data("could not load the model or the image\n".utf8))
        exit(1)
    }
    for hit in detector.scan(frame, region: nil) {
        print(hit.label, String(format: "%.2f", hit.score), hit.box.x, hit.box.y, hit.box.w, hit.box.h)
    }
    exit(0)
}

func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, nil, &pb)
    guard let pb else { return nil }
    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: image.width, height: image.height,
                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pb
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
