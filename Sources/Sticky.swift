// Sticky pad: one persistent note that floats over everything.
// Toggle: double-tap the trigger key (or ⌃⇧N, or the menu). Esc hides.
// Text autosaves on every keystroke to ~/Library/Application Support/Point/sticky.txt and stays until you
// delete it. Max 1440 chars. With the pad open, hold the trigger key to dictate into it.

import Cocoa

let STICKY_FILE = POINT_DIR.appendingPathComponent("sticky.txt")
let NOTE_MAX_CHARS = 1440

// Frosted glass that follows light/dark; one amber dot keeps the "sticky" cue.
private let NOTE_ACCENT = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.18, alpha: 1.0)
private let NOTE_RADIUS: CGFloat = 14

final class StickyNoteController: NSObject, NSTextViewDelegate {
    static let shared = StickyNoteController()

    private static let originKey = "stickyOrigin"

    private var panel: StickyPanel?
    private var textView: NSTextView!
    private var counter: NSTextField!
    private var hint: NSTextField!
    private var returnTo: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil { build() }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { returnTo = front }

        textView.string = load()
        hint.stringValue = "esc to hide · double-tap \(TriggerKey.current.symbol)"
        updateCounter()

        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        save()
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
        panel.orderOut(nil)
        returnTo?.activate()
        returnTo = nil
    }

    // ─── Persistence ─────────────────────────────────────────────────────────

    private func load() -> String {
        let text = (try? String(contentsOf: STICKY_FILE, encoding: .utf8)) ?? ""
        return String(text.prefix(NOTE_MAX_CHARS))
    }

    private func save() {
        guard let textView else { return }
        do {
            try FileManager.default.createDirectory(at: POINT_DIR, withIntermediateDirectories: true)
            try textView.string.write(to: STICKY_FILE, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Point: sticky save failed: \(error)")
        }
    }

    /// Last position the pad was left at, if it's still on a connected screen.
    private func savedOrigin(for size: NSSize) -> NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: Self.originKey) else { return nil }
        let p = NSPointFromString(s)
        let frame = NSRect(origin: p, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) } ? p : nil
    }

    // ─── UI ──────────────────────────────────────────────────────────────────

    private func build() {
        let size = NSSize(width: 440, height: 260)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let origin = savedOrigin(for: size)
            ?? NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2 + vf.height * 0.12)

        let p = StickyPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        // Appear on whatever Space you're on (incl. over full-screen apps).
        // Note: .canJoinAllSpaces + .moveToActiveSpace together throws — keep only one.
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        p.onEscape = { [weak self] in self?.hide() }

        let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.maskImage = Self.roundedMask(radius: NOTE_RADIUS)
        bg.wantsLayer = true
        bg.layer?.cornerRadius = NOTE_RADIUS
        bg.layer?.borderWidth = 0.5
        bg.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let dot = NSView(frame: NSRect(x: 18, y: size.height - 24, width: 6, height: 6))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NOTE_ACCENT.cgColor
        dot.layer?.cornerRadius = 3
        bg.addSubview(dot)

        let title = NSTextField(labelWithString: "STICKY")
        title.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        title.textColor = .tertiaryLabelColor
        title.attributedStringValue = NSAttributedString(string: "STICKY", attributes: [.kern: 1.2, .font: title.font!, .foregroundColor: NSColor.tertiaryLabelColor])
        title.frame = NSRect(x: 30, y: size.height - 28, width: 200, height: 14)
        bg.addSubview(title)

        let scroll = NSScrollView(frame: NSRect(x: 12, y: 32, width: size.width - 24, height: size.height - 68))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder

        let tv = NSTextView(frame: scroll.contentView.bounds)
        tv.autoresizingMask = [.width]
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        tv.textColor = .labelColor
        tv.insertionPointColor = NOTE_ACCENT
        tv.selectedTextAttributes = [.backgroundColor: NOTE_ACCENT.withAlphaComponent(0.3)]
        tv.textContainerInset = NSSize(width: 6, height: 4)
        let para = NSMutableParagraphStyle(); para.lineSpacing = 3
        tv.defaultParagraphStyle = para
        tv.typingAttributes[.paragraphStyle] = para
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.delegate = self
        scroll.documentView = tv
        bg.addSubview(scroll)

        let hint = NSTextField(labelWithString: "")
        self.hint = hint
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .quaternaryLabelColor
        hint.frame = NSRect(x: 18, y: 12, width: 300, height: 13)
        bg.addSubview(hint)

        let count = NSTextField(labelWithString: "")
        count.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        count.alignment = .right
        count.frame = NSRect(x: size.width - 108, y: 12, width: 90, height: 13)
        bg.addSubview(count)

        p.contentView = bg
        panel = p
        textView = tv
        counter = count
    }

    /// Stretchable rounded-rect mask so the frosted glass gets real rounded corners.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let d = radius * 2 + 1
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    private func updateCounter() {
        let n = textView.string.count
        // the count only matters near the cap; stay out of the way until then
        counter.isHidden = n < NOTE_MAX_CHARS * 8 / 10
        counter.stringValue = "\(NOTE_MAX_CHARS - n) left"
        counter.textColor = n >= NOTE_MAX_CHARS ? .systemRed : .tertiaryLabelColor
    }

    // Hard cap at NOTE_MAX_CHARS (handles typing, paste, and dictation).
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                  replacementString text: String?) -> Bool {
        guard let text else { return true }
        let current = textView.string as NSString
        let next = current.replacingCharacters(in: range, with: text)
        if next.count <= NOTE_MAX_CHARS { return true }
        let room = NOTE_MAX_CHARS - (current.length - range.length)
        if room > 0 { textView.insertText(String(text.prefix(room)), replacementRange: range) }
        NSSound.beep()
        return false
    }

    func textDidChange(_ notification: Notification) {
        updateCounter()
        save()
    }
}

final class StickyPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    // LSUIElement apps have no Edit menu, so ⌘V/⌘C/… never reach the text view.
    // Route the standard editing shortcuts by hand (also how dictation pastes in).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }
        let shift = flags.contains(.shift)
        let action: Selector?
        switch key {
        case "v": action = #selector(NSText.paste(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "x": action = #selector(NSText.cut(_:))
        case "a": action = #selector(NSText.selectAll(_:))
        case "z": action = shift ? Selector(("redo:")) : Selector(("undo:"))
        default: action = nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
