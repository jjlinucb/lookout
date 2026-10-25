import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// One screenshot per display, in memory, through ScreenCaptureKit. Taken at
/// normal (not Retina) resolution: a quarter of the pixels, and the model
/// shrinks every image to 320 pixels anyway. Lookout's own windows and the
/// cursor are left out. Nothing is ever written to disk.
final class Capture {
    private var content: SCShareableContent?
    private var fetched = Date.distantPast

    /// Screen Recording permission. Asking shows macOS's prompt once.
    static var allowed: Bool { CGPreflightScreenCaptureAccess() }
    static func ask() { _ = CGRequestScreenCaptureAccess() }

    func frames() async throws -> [CVPixelBuffer] {
        // The list of displays changes rarely; asking for it costs more than a screenshot.
        if content == nil || Date().timeIntervalSince(fetched) > 30 {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            fetched = Date()
        }
        guard let content else { return [] }
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var out: [CVPixelBuffer] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            config.captureResolution = .nominal
            do {
                let sample = try await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config)
                if let pb = sample.imageBuffer { out.append(pb) }
            } catch {
                // A display was unplugged: look again for displays next time.
                self.content = nil
                throw error
            }
        }
        return out
    }
}
