// The Right Option gesture.
//   hold + talk            → dictation pasted at the text cursor (and left on the clipboard)
//   hold + talk + draw loop → transcript + path to a full-screen PNG with your loop drawn on it
//   double-tap             → toggle the sticky pad (Sticky.swift)

import Cocoa
import AVFoundation

let OVERLAY_DELAY: TimeInterval = 0.15         // avoid flashing on quick taps
let MIN_HOLD: TimeInterval = 0.4               // shorter holds with no drawing = ignored
let LOOP_COLOR = NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.25, alpha: 1.0)
let LOOP_WIDTH: CGFloat = 5.0
let MIN_LOOP_LENGTH: CGFloat = 40               // shorter marks = a click/twitch, not a loop

/// A stroke counts as a deliberate loop only if its path is long enough.
func isLoop(_ stroke: [NSPoint]) -> Bool {
    var length: CGFloat = 0
    for (a, b) in zip(stroke, stroke.dropFirst()) {
        length += hypot(b.x - a.x, b.y - a.y)
        if length >= MIN_LOOP_LENGTH { return true }
    }
    return false
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

func postCommandV() {
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        if let e = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: down) {
            e.flags = .maskCommand
            e.post(tap: .cghidEventTap)
        }
    }
}

// ─── Controller: watches Right Option ────────────────────────────────────────

let TAP_MAX: TimeInterval = 0.25            // a press shorter than this is a "tap"
let DOUBLE_TAP_WINDOW: TimeInterval = 0.45  // two taps within this → toggle sticky pad

final class CircleTalkController {
    private var monitors: [Any] = []
    private var held = false
    private var downAt = Date.distantPast
    private var lastTapAt = Date.distantPast
    private var otherKeyDuringHold = false
    private var session: CircleSession?
    private var pendingOverlay: DispatchWorkItem?

    func install() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in
            self?.handle($0); return $0
        }) {
            monitors.append(m)
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                NSLog("Point: microphone %@", ok ? "granted" : "denied")
            }
        case .denied, .restricted:
            NSLog("Point: ⚠️ microphone denied — circles will work, transcripts won't")
        default: break
        }
        AppleTranscriber.prewarm()
        NSLog("Point: ✅ active — hold %@ to dictate, draw to add a screenshot, double-tap for sticky", TriggerKey.current.symbol)
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let key = TriggerKey.current
            guard event.keyCode == key.keyCode else { return }
            let down = key.isDown(event.modifierFlags)
            if down && !held {
                held = true
                downAt = Date()
                otherKeyDuringHold = false
                begin()
            } else if !down && held {
                held = false
                let wasTap = Date().timeIntervalSince(downAt) < TAP_MAX
                    && !otherKeyDuringHold
                    && !(session?.strokes.contains(where: isLoop) ?? false)
                finish()
                if wasTap { registerTap() }
            }
        case .keyDown:
            // Any key while holding means the trigger was part of a shortcut (or Esc) — bail out.
            if held {
                otherKeyDuringHold = true
                if session != nil { cancel() }
            }
        default:
            break
        }
    }

    /// Double-tap the trigger key toggles the sticky pad. Single taps are ignored.
    private func registerTap() {
        let now = Date()
        if now.timeIntervalSince(lastTapAt) < DOUBLE_TAP_WINDOW {
            lastTapAt = .distantPast
            StickyNoteController.shared.toggle()
        } else {
            lastTapAt = now
        }
    }

    private func begin() {
        guard session == nil else { return }
        let s = CircleSession(transcriber: AppleTranscriber())
        s.onDone = { [weak self, weak s] in
            if let s, self?.session === s { self?.session = nil }
        }
        session = s
        s.start()
        let work = DispatchWorkItem { [weak s] in s?.showOverlay() }
        pendingOverlay = work
        DispatchQueue.main.asyncAfter(deadline: .now() + OVERLAY_DELAY, execute: work)
    }

    private func finish() {
        pendingOverlay?.cancel()
        session?.finish()
    }

    private func cancel() {
        pendingOverlay?.cancel()
        session?.cancel()
        session = nil
    }
}

// ─── One gesture ─────────────────────────────────────────────────────────────

final class CircleSession {
    var onDone: (() -> Void)?

    private let transcriber: Transcriber
    private let keyDown = Date()
    private let id = Int(Date().timeIntervalSince1970 * 1000)
    private let targetApp = NSWorkspace.shared.frontmostApplication
    private var overlays: [OverlayPanel] = []
    private var ended = false
    private var marks: [String: Int] = [:]       // stage → ms since key down

    private(set) var strokes: [[NSPoint]] = []   // global (Cocoa) screen coordinates
    private(set) var liveText = ""

    private var audioURL: URL { CAPTURES_DIR.appendingPathComponent("point_\(id).wav") }
    private var metaURL: URL { CAPTURES_DIR.appendingPathComponent("point_\(id).json") }

    init(transcriber: Transcriber) {
        self.transcriber = transcriber
        transcriber.onPartial = { [weak self] text in
            self?.liveText = text
            self?.redraw()
        }
        transcriber.onFirstAudio = { [weak self] in self?.mark("mic_first_audio") }
    }

    private func mark(_ stage: String) {
        if marks[stage] == nil { marks[stage] = Int(Date().timeIntervalSince(keyDown) * 1000) }
    }

    func start() {
        try? FileManager.default.createDirectory(at: CAPTURES_DIR, withIntermediateDirectories: true)
        transcriber.start(recordingTo: audioURL)
    }

    func showOverlay() {
        guard !ended, overlays.isEmpty else { return }
        overlays = NSScreen.screens.map { OverlayPanel(screen: $0, session: self) }
        overlays.forEach { $0.orderFrontRegardless() }
        mark("overlay_shown")
    }

    func beginStroke(_ p: NSPoint) { strokes.append([p]); redraw() }

    func extendStroke(_ p: NSPoint) {
        guard !strokes.isEmpty else { return }
        strokes[strokes.count - 1].append(p)
        redraw()
    }

    private func redraw() { overlays.forEach { $0.contentView?.needsDisplay = true } }

    private func hideOverlay() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
    }

    func cancel() {
        guard !ended else { return }
        ended = true
        hideOverlay()
        transcriber.cancel()
        try? FileManager.default.removeItem(at: audioURL)
        onDone?()
    }

    func finish() {
        guard !ended else { return }
        mark("key_up")
        let drew = strokes.contains(where: isLoop)
        if !drew && Date().timeIntervalSince(keyDown) < MIN_HOLD {
            cancel()
            return
        }
        ended = true
        hideOverlay()

        let screen = targetScreen()
        let strokes = self.strokes
        let target = targetApp
        let id = self.id

        Task {
            let transcript = await transcriber.stop()
            await MainActor.run { self.mark("transcript_ready") }
            if !drew {
                // No loop drawn = plain dictation: transcript → clipboard → paste at the caret.
                await MainActor.run {
                    if transcript.isEmpty {
                        try? FileManager.default.removeItem(at: self.audioURL)
                        showToast("Didn't catch anything")
                        self.onDone?()
                        return
                    }
                    pasteText(transcript, target: target) {
                        self.mark("pasted")
                        self.writeMetadata(transcript: transcript, screenshot: nil, kind: "dictation")
                        self.onDone?()
                    }
                }
                return
            }
            // Let the window server drop the overlay before capturing.
            try? await Task.sleep(nanoseconds: 80_000_000)
            let path = await Task.detached { captureAndCompose(screen: screen, strokes: strokes, id: id) }.value
            await MainActor.run {
                self.mark("screenshot_saved")
                guard let path else {
                    self.writeMetadata(transcript: transcript, screenshot: nil, kind: "circle_failed")
                    showToast("⚠️ Screenshot failed — check Screen Recording permission")
                    self.onDone?()
                    return
                }
                deliver(path: path, transcript: transcript, target: target) {
                    self.mark("pasted")
                    self.writeMetadata(transcript: transcript, screenshot: path, kind: "circle")
                    self.onDone?()
                }
            }
        }
    }

    /// One JSON per gesture. `reference` is left null — fill it in by hand to score accuracy.
    private func writeMetadata(transcript: String, screenshot: String?, kind: String) {
        let audioPath = FileManager.default.fileExists(atPath: audioURL.path) ? audioURL.path : nil
        var audioSeconds: Double?
        if let audioPath, let f = try? AVAudioFile(forReading: URL(fileURLWithPath: audioPath)) {
            audioSeconds = (Double(f.length) / f.fileFormat.sampleRate * 100).rounded() / 100
        }
        let meta: [String: Any] = [
            "id": id,
            "created_at": ISO8601DateFormatter().string(from: keyDown),
            "engine": transcriber.engineName,
            "locale": Locale.current.identifier,
            "transcript": transcript,
            "reference": NSNull(),
            "kind": kind,
            "screenshot": screenshot ?? NSNull(),
            "audio": audioPath ?? NSNull(),
            "audio_seconds": audioSeconds ?? NSNull(),
            "app": targetApp?.localizedName ?? NSNull(),
            "bundle_id": targetApp?.bundleIdentifier ?? NSNull(),
            "strokes": strokes.filter(isLoop).count,
            "timings_ms": marks,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: metaURL)
        } catch {
            NSLog("Point: metadata write failed: \(error)")
        }
    }

    /// The screen where drawing started, else the one under the cursor.
    private func targetScreen() -> NSRect {
        let anchor = strokes.first(where: isLoop)?.first ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        return screen.frame
    }
}

// ─── Capture + compose + deliver ─────────────────────────────────────────────

/// Screenshot `screenFrame` (Cocoa coords), draw strokes onto it, save PNG. Returns the path.
func captureAndCompose(screen screenFrame: NSRect, strokes: [[NSPoint]], id: Int) -> String? {
    // screencapture -R wants top-left-origin global coordinates.
    let mainHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
    let topY = mainHeight - screenFrame.maxY
    let rect = String(format: "%.0f,%.0f,%.0f,%.0f",
                      screenFrame.minX, topY, screenFrame.width, screenFrame.height)
    let tmp = NSTemporaryDirectory() + "point_capture_\(Int(Date().timeIntervalSince1970 * 1000)).png"
    defer { try? FileManager.default.removeItem(atPath: tmp) }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-t", "png", "-R", rect, tmp]
    do { try task.run() } catch {
        NSLog("Point: screencapture failed: \(error)")
        return nil
    }
    task.waitUntilExit()

    guard task.terminationStatus == 0,
          let img = NSImage(contentsOfFile: tmp),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        NSLog("Point: capture produced no image (Screen Recording permission?)")
        return nil
    }

    let w = cg.width, h = cg.height
    let scale = CGFloat(w) / screenFrame.width
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: cg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setStrokeColor(LOOP_COLOR.cgColor)
    ctx.setLineWidth(LOOP_WIDTH * scale)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for stroke in strokes where isLoop(stroke) {
        // Both CG and Cocoa are bottom-left origin; just translate + scale.
        let pts = stroke.map {
            CGPoint(x: ($0.x - screenFrame.minX) * scale, y: ($0.y - screenFrame.minY) * scale)
        }
        ctx.addLines(between: pts)
        ctx.strokePath()
    }

    guard let out = ctx.makeImage(),
          let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    else { return nil }

    try? FileManager.default.createDirectory(at: CAPTURES_DIR, withIntermediateDirectories: true)
    let dest = CAPTURES_DIR.appendingPathComponent("point_\(id).png")
    do { try png.write(to: dest) } catch {
        NSLog("Point: write failed: \(error)")
        return nil
    }
    return dest.path
}

func deliver(path: String, transcript: String, target: NSRunningApplication?,
             onPasted: @escaping () -> Void) {
    var text = transcript.isEmpty ? "" : transcript + "\n\n"
    text += "[Screenshot: \(path)]"
    NSLog("Point: circle → %@ (%d chars spoken)", path, transcript.count)
    DispatchQueue.global(qos: .utility).async { SauronHook.register(screenshot: path, app: target) }
    pasteText(text, target: target, onPasted: onPasted)
}

/// Put `text` on the clipboard (it stays there) and paste it at the text caret of `target`.
func pasteText(_ text: String, target: NSRunningApplication?, onPasted: @escaping () -> Void) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    NSLog("Point: pasting %d chars into %@", text.count, target?.localizedName ?? "front app")

    // Overlay never took focus, but re-assert in case something else did.
    if let target, NSWorkspace.shared.frontmostApplication != target { target.activate() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        postCommandV()
        onPasted()
    }
}

// ─── Toast ───────────────────────────────────────────────────────────────────

private var activeToast: NSPanel?

/// Small non-activating pill at the bottom of the screen under the cursor; fades after ~1.6s.
func showToast(_ message: String) {
    activeToast?.orderOut(nil)

    let label = NSTextField(labelWithString: message)
    label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
    label.textColor = .white
    label.sizeToFit()

    let pad: CGFloat = 14
    let size = NSSize(width: label.frame.width + pad * 2, height: label.frame.height + pad)
    let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        ?? NSScreen.main ?? NSScreen.screens[0]
    let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 60)

    let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .screenSaver
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let bg = NSView(frame: NSRect(origin: .zero, size: size))
    bg.wantsLayer = true
    bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
    bg.layer?.cornerRadius = size.height / 2
    label.frame.origin = NSPoint(x: pad, y: pad / 2)
    bg.addSubview(label)
    panel.contentView = bg
    panel.orderFrontRegardless()
    activeToast = panel

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
            panel.orderOut(nil)
            if activeToast === panel { activeToast = nil }
        }
    }
}

// ─── Overlay ─────────────────────────────────────────────────────────────────

final class OverlayPanel: NSPanel {
    init(screen: NSScreen, session: CircleSession) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(screen.frame, display: false)
        contentView = OverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screenFrame: screen.frame, session: session)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayView: NSView {
    private let screenFrame: NSRect
    private weak var session: CircleSession?

    init(frame: NSRect, screenFrame: NSRect, session: CircleSession) {
        self.screenFrame = screenFrame
        self.session = session
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { session?.beginStroke(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { session?.extendStroke(NSEvent.mouseLocation) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()

        guard let session else { return }

        LOOP_COLOR.setStroke()
        for stroke in session.strokes where stroke.count > 1 {
            let path = NSBezierPath()
            path.lineWidth = LOOP_WIDTH
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: local(stroke[0]))
            stroke.dropFirst().forEach { path.line(to: local($0)) }
            path.stroke()
        }

        // Only the screen under the cursor shows the transcript pill.
        guard NSMouseInRect(NSEvent.mouseLocation, screenFrame, false) else { return }
        let hint = !session.strokes.contains(where: isLoop)
            ? "● Listening — talk to dictate · circle to add a screenshot"
            : "● Listening — will paste text + screenshot"
        drawPill(session.liveText.isEmpty ? hint : "● " + tail(session.liveText))
    }

    private func local(_ p: NSPoint) -> NSPoint {
        NSPoint(x: p.x - screenFrame.minX, y: p.y - screenFrame.minY)
    }

    private func tail(_ s: String, max: Int = 110) -> String {
        s.count <= max ? s : "…" + s.suffix(max)
    }

    private func drawPill(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pad: CGFloat = 14
        let pill = NSRect(x: (bounds.width - size.width) / 2 - pad, y: 60,
                          width: size.width + pad * 2, height: size.height + pad)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        str.draw(at: NSPoint(x: pill.minX + pad, y: pill.minY + pad / 2))
    }
}
