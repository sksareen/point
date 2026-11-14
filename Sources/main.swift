// Point — hold Right Option to talk to your computer about what's on screen.
//
//   hold trigger + talk              → dictation, pasted at your text cursor
//   hold trigger + talk + draw loop  → + path to a screenshot with your loop on it
//   double-tap trigger (or ⌃⇧N)      → toggle a persistent sticky pad
// The trigger defaults to Right ⌥ and can be changed from the menu (TriggerKey.swift).
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
        NotificationCenter.default.addObserver(forName: TriggerKey.changed, object: nil, queue: .main) { [weak self] _ in
            self?.refreshTriggerLabels()
        }
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
        let open = NSMenuItem(title: "Open Point…", action: #selector(openWindow), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        howItem.isEnabled = false
        menu.addItem(howItem)
        stickyItem.action = #selector(toggleSticky)
        stickyItem.target = self
        menu.addItem(stickyItem)

        let triggerMenu = NSMenu()
        for key in TriggerKey.allCases {
            let item = NSMenuItem(title: key.menuTitle, action: #selector(pickTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key.rawValue
            triggerMenu.addItem(item)
            triggerItems.append(item)
        }
        let trigger = NSMenuItem(title: "Trigger key", action: nil, keyEquivalent: "")
        trigger.submenu = triggerMenu
        menu.addItem(trigger)
        refreshTriggerLabels()
        addDevModeItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Point", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc func toggleSticky() { StickyNoteController.shared.toggle() }
    @objc func openWindow() { PointWindowController.shared.show(.captures) }
    @objc func openSettings() { PointWindowController.shared.show(.settings) }

    // ─── Trigger key setting ─────────────────────────────────────────────────

    private let howItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let stickyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var triggerItems: [NSMenuItem] = []

    @objc func pickTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let key = TriggerKey(rawValue: raw) else { return }
        TriggerKey.current = key
        refreshTriggerLabels()
        NSLog("Point: trigger key → %@", key.symbol)
    }

    private func refreshTriggerLabels() {
        let key = TriggerKey.current
        howItem.title = "Hold \(key.symbol): talk → dictate · draw → + screenshot"
        stickyItem.title = "Sticky pad  (double-tap \(key.symbol) · ⌃⇧N)"
        for item in triggerItems {
            item.state = (item.representedObject as? String) == key.rawValue ? .on : .off
        }
    }

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

    /// ⌃⇧N — alternative to double-tapping the trigger key.
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
