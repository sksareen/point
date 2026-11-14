// Point — hold Right Option to talk to your computer about what's on screen.
//
//   hold Right ⌥ + talk              → dictation, pasted at your text cursor
//   hold Right ⌥ + talk + draw loop  → + path to a screenshot with your loop on it
//   double-tap Right ⌥ (or ⌃⇧N)      → toggle a persistent sticky pad
//
// Install: ./install.sh   (builds, signs, copies to /Applications, launches)
// (This file must be main.swift: it holds the top-level app entry point.)

import Cocoa

// ─── Paths ───────────────────────────────────────────────────────────────────

let POINT_DIR = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Point")
/// Each gesture saves point_<id>.png (if you drew), .wav (what the model heard), .json (transcript + timings).
let CAPTURES_DIR = POINT_DIR.appendingPathComponent("captures")

// ─── Entry point ─────────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let appDelegate = PointAppDelegate()
app.delegate = appDelegate
app.run()

// ─── App delegate ────────────────────────────────────────────────────────────

final class PointAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let gesture = CircleTalkController()
    private var keyMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        requireAccessibility()
        NSLog("Point %@ launched from %@", APP_VERSION, Bundle.main.bundlePath)
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: "Point") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "☝︎"
        }

        let menu = NSMenu()
        let how = NSMenuItem(title: "Hold Right ⌥: talk → dictate · draw → + screenshot",
                             action: nil, keyEquivalent: "")
        how.isEnabled = false
        menu.addItem(how)
        menu.addItem(withTitle: "Sticky pad  (double-tap Right ⌥ · ⌃⇧N)",
                     action: #selector(toggleSticky), keyEquivalent: "")
        addDevModeItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Point", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func toggleSticky() { StickyNoteController.shared.toggle() }

    // Global key monitoring needs Accessibility. Prompt once, then poll until granted.
    private func requireAccessibility() {
        if AXIsProcessTrusted() {
            start()
            return
        }
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        NSLog("Point: ⚠️ Accessibility not granted — system prompt shown. Waiting...")
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            NSLog("Point: ✅ Accessibility granted")
            self?.start()
        }
    }

    private func start() {
        gesture.install()
        installStickyHotkey()
    }

    /// ⌃⇧N — alternative to double-tapping Right ⌥.
    private func installStickyHotkey() {
        func isHotkey(_ e: NSEvent) -> Bool {
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return e.keyCode == 45 && flags == [.control, .shift]
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { e in
            if isHotkey(e) { DispatchQueue.main.async { StickyNoteController.shared.toggle() } }
        }) { keyMonitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { e in
            guard isHotkey(e) else { return e }
            DispatchQueue.main.async { StickyNoteController.shared.toggle() }
            return nil
        }) { keyMonitors.append(m) }
    }
}
