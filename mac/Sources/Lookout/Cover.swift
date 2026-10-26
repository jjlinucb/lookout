import AppKit

/// Black windows over every display, above everything including full-screen
/// apps, with two ways out so a wrong flag never locks the screen.
@MainActor
final class Cover {
    private var windows: [NSWindow] = []
    var onContinue: () -> Void = {}
    var onWrongFlag: () -> Void = {}

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    func show(_ message: String, pauseMinutes: Int) {
        hide()
        for screen in NSScreen.screens {
            let f = screen.frame
            let w = Panel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.backgroundColor = .black
            w.isOpaque = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            w.setFrame(f, display: false)

            let label = NSTextField(labelWithString: message)
            label.font = .systemFont(ofSize: 28)
            label.textColor = NSColor(white: 0.85, alpha: 1)
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
