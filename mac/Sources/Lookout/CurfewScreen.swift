import AppKit

/// The curfew: a calm screen over every display with the time and one way
/// out, the working-late pass. Unlike the flag cover it never lifts by itself.
/// Also the small notice before it starts.
@MainActor
final class CurfewScreen {
    private var windows: [NSWindow] = []
    private var clocks: [NSTextField] = []
    private var notice: NSWindow?
    var onPass: () -> Void = {}
    var isShown: Bool { !windows.isEmpty }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = NSColor(white: 0.9, alpha: 1)
        l.alignment = .center
        return l
    }

    private static func time() -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: Date())
    }

    func show(until end: String, passMinutes: Int) {
        guard windows.isEmpty else {
            clocks.forEach { $0.stringValue = Self.time() }
            return
        }
        hideNotice()
        for screen in NSScreen.screens {
            let f = screen.frame
            let w = Panel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1)
            w.isOpaque = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            w.setFrame(f, display: false)

            let clock = Self.label(Self.time(), size: 64, weight: .light)
            clock.frame = NSRect(x: 0, y: f.height / 2 + 30, width: f.width, height: 80)
            clocks.append(clock)
            let words = Self.label("Rest now. See you at \(end).", size: 26)
            words.frame = NSRect(x: 0, y: f.height / 2 - 30, width: f.width, height: 40)

            let b = NSButton(title: "", target: self, action: #selector(passClicked))
            b.isBordered = false
            b.attributedTitle = NSAttributedString(string: "Working late (\(passMinutes) min)", attributes: [
                .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 17, weight: .medium)])
            b.wantsLayer = true
            b.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
            b.layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
            b.layer?.borderWidth = 1.5
            b.layer?.cornerRadius = 10
            b.frame = NSRect(x: f.width / 2 - 130, y: f.height / 2 - 110, width: 260, height: 44)

            [clock, words, b].forEach { w.contentView?.addSubview($0) }
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        clocks = []
    }

    /// A small note at the top of the main display. It can be closed, and
    /// goes by itself after a few minutes.
    func showNotice(_ text: String) {
        guard notice == nil, let screen = NSScreen.main else { return }
        let size = NSSize(width: 420, height: 64)
        let f = NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 16,
                       width: size.width, height: size.height)
        let w = Panel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = .statusBar
        w.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 0.95)
        w.isOpaque = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.contentView?.wantsLayer = true
        w.contentView?.layer?.cornerRadius = 12
        let l = Self.label(text, size: 16, weight: .medium)
        l.frame = NSRect(x: 16, y: 20, width: size.width - 72, height: 24)
        let x = NSButton(title: "", target: self, action: #selector(closeNotice))
        x.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        x.contentTintColor = .white
        x.isBordered = false
        x.frame = NSRect(x: size.width - 48, y: 16, width: 32, height: 32)
        [l, x].forEach { w.contentView?.addSubview($0) }
        w.orderFrontRegardless()
        notice = w
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            self?.hideNotice()
        }
    }

    func hideNotice() {
        notice?.orderOut(nil)
        notice = nil
    }

    @objc private func passClicked() { onPass() }
    @objc private func closeNotice() { hideNotice() }
}
