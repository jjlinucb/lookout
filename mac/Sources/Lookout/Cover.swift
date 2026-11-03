import AppKit
import CoreImage

/// Windows over every display, above everything including full-screen apps,
/// with two ways out so a wrong flag never locks the screen. Behind the
/// words is the screen itself, blurred past recognition, or black.
@MainActor
final class Cover {
    private var windows: [NSWindow] = []
    var onContinue: () -> Void = {}
    var onWrongFlag: () -> Void = {}

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    /// Pixelated in big blocks, then blurred and darkened: only colour is left.
    static func blurred(_ frame: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: frame)
        let size = image.extent.size
        let block = max(size.width, size.height) / 16
        let out = image
            .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: block])
            .clampedToExtent()
            .applyingGaussianBlur(sigma: block)
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.35, kCIInputSaturationKey: 0.8])
            .cropped(to: image.extent)
        return CIContext().createCGImage(out, from: image.extent)
    }

    func show(_ message: String, pauseMinutes: Int, backgrounds: [CGDirectDisplayID: CGImage] = [:]) {
        hide()
        for screen in NSScreen.screens {
            let f = screen.frame
            let w = Panel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.backgroundColor = .black
            w.isOpaque = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            w.setFrame(f, display: false)
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if let id, let image = backgrounds[id] {
                let back = NSImageView(frame: NSRect(origin: .zero, size: f.size))
                back.image = NSImage(cgImage: image, size: f.size)
                back.imageScaling = .scaleAxesIndependently
                w.contentView?.addSubview(back)
                // A dark tint so the white words read on a blurred white page.
                let tint = NSView(frame: NSRect(origin: .zero, size: f.size))
                tint.wantsLayer = true
                tint.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor
                w.contentView?.addSubview(tint)
            }

            let label = NSTextField(labelWithString: message)
            label.font = .systemFont(ofSize: 28)
            label.textColor = .white
            label.alignment = .center
            label.frame = NSRect(x: 0, y: f.height / 2 - 30, width: f.width, height: 60)
            w.contentView?.addSubview(label)

            let mid = f.width / 2
            let buttons: [(String, Selector, CGFloat)] = [
                ("Continue", #selector(continueClicked), mid - 265),
                ("Wrong flag: pause \(pauseMinutes) min", #selector(wrongFlagClicked), mid + 15),
            ]
            // Drawn by hand: the standard grey buttons all but vanish on black.
            for (title, action, x) in buttons {
                let b = NSButton(title: "", target: self, action: action)
                b.isBordered = false
                b.attributedTitle = NSAttributedString(string: title, attributes: [
                    .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 17, weight: .medium)])
                b.wantsLayer = true
                b.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
                b.layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
                b.layer?.borderWidth = 1.5
                b.layer?.cornerRadius = 10
                b.frame = NSRect(x: x, y: f.height / 2 - 100, width: 250, height: 44)
                w.contentView?.addSubview(b)
            }
            // A white X in the top right corner, the same as Continue.
            let x = NSButton(title: "", target: self, action: #selector(continueClicked))
            x.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
                .withSymbolConfiguration(.init(pointSize: 28, weight: .semibold))
            x.contentTintColor = .white
            x.isBordered = false
            x.frame = NSRect(x: f.width - 84, y: f.height - 84, width: 56, height: 56)
            w.contentView?.addSubview(x)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    @objc private func continueClicked() { onContinue() }
    @objc private func wrongFlagClicked() { onWrongFlag() }
}
