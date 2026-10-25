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
                ("Continue", #selector(continueClicked), mid - 230),
                ("Wrong flag: pause \(pauseMinutes) min", #selector(wrongFlagClicked), mid + 10),
            ]
            for (title, action, x) in buttons {
                let b = NSButton(title: title, target: self, action: action)
                b.frame = NSRect(x: x, y: f.height / 2 - 90, width: 220, height: 32)
                w.contentView?.addSubview(b)
            }
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
