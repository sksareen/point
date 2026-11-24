// First-launch onboarding: welcome → permissions → try talking → try pointing → done.
// Opens once on a fresh install, and any time from the menu (Welcome to Point…).

import AVFoundation
import SwiftUI

/// While set, a finished capture is handed here instead of being pasted into the front app.
/// The onboarding practice steps use it so a first try lands in the window, not somewhere random.
var CAPTURE_INTERCEPT: ((_ transcript: String, _ screenshot: String?) -> Void)?

final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()
    private static let doneKey = "onboardingDone"
    private var window: NSWindow?

    /// True on a fresh install. Existing installs (Point's data folder exists) skip it.
    /// Call once at launch, before anything creates the data folder.
    static func noteLaunch() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: doneKey) == nil else { return }
        if FileManager.default.fileExists(atPath: POINT_DIR.path) { defaults.set(true, forKey: doneKey) }
    }

    static var needed: Bool { !UserDefaults.standard.bool(forKey: doneKey) }

    func show() {
        if window == nil {
            let model = OnboardingModel(onFinish: { [weak self] in self?.finish() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: model)))
            w.title = "Welcome to Point"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(OB.bg)
            w.setContentSize(NSSize(width: 760, height: 540))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        AppPresence.windowWillShow()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        CAPTURE_INTERCEPT = nil
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        window = nil
    }
}

// ─── Look ────────────────────────────────────────────────────────────────────

private enum OB {
    static let bg = Color(red: 0.102, green: 0.129, blue: 0.165)        // #1A212A
    static let panel = Color(red: 0.063, green: 0.086, blue: 0.114)     // #10161D
    static let raised = Color(red: 0.145, green: 0.180, blue: 0.224)    // #252E39
    static let line = Color(red: 0.165, green: 0.200, blue: 0.247)      // #2A333F
    static let ink = Color(red: 0.902, green: 0.925, blue: 0.949)       // #E6ECF2
    static let muted = Color(red: 0.592, green: 0.647, blue: 0.706)     // #97A5B4
    static let red = Color(red: 0.898, green: 0.212, blue: 0.290)       // #E5364A
    static let loop = Color(red: 1.0, green: 0.278, blue: 0.341)        // #FF4757
    static let green = Color(red: 0.373, green: 0.831, blue: 0.596)     // #5FD498
    static let dot = Color(red: 0.227, green: 0.275, blue: 0.329)       // #3A4654
}

private struct PrimaryButton: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(enabled ? Color.white : OB.muted)
            .padding(.horizontal, 26).frame(minHeight: 44)
            .background(Capsule().fill(enabled ? OB.red : OB.raised))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OB.muted)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// ─── Model ───────────────────────────────────────────────────────────────────

final class OnboardingModel: ObservableObject {
    @Published var step = 0 { didSet { stepChanged() } }
    @Published var perms = PermissionStatus.current()
    @Published var said = ""
    @Published var circled: String?
    @Published var circleHint = false
    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var key = TriggerKey.current
    let onFinish: () -> Void
    private var timer: Timer?

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        // For screenshots and testing: `--onboarding-step=3` opens on that step.
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--onboarding-step=") }),
           let n = Int(arg.dropFirst("--onboarding-step=".count)), (0...4).contains(n) {
            step = n
            stepChanged()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let now = PermissionStatus.current()
            if let self, now.accessibility != self.perms.accessibility || now.microphone != self.perms.microphone
                || now.screen != self.perms.screen { self.perms = now }
        }
    }

    deinit { timer?.invalidate() }

    private func stepChanged() {
        switch step {
        case 2:
            CAPTURE_INTERCEPT = { [weak self] text, _ in self?.said = text }
        case 3:
            CAPTURE_INTERCEPT = { [weak self] text, shot in
                if shot != nil { self?.circled = text; self?.circleHint = false } else { self?.circleHint = true }
            }
        default:
            CAPTURE_INTERCEPT = nil
        }
    }

    func allowAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        openPane("Privacy_Accessibility")
    }

    func allowMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        } else {
            openPane("Privacy_Microphone")
        }
    }

    func allowScreen() {
        if !CGRequestScreenCaptureAccess() { openPane("Privacy_ScreenCapture") }
    }

    private func openPane(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}

// ─── View ────────────────────────────────────────────────────────────────────

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case 0: welcome
                case 1: permissions
                case 2: talk
                case 3: circle
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(.init(top: 48, leading: 48, bottom: 32, trailing: 48))
        .frame(width: 760, height: 540)
        .focusEffectDisabled()
        .background(OB.bg)
        .foregroundStyle(OB.ink)
        .preferredColorScheme(.dark)
    }

    private func heading(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 30, weight: .heavy)).tracking(-0.6)
            Text(sub).font(.system(size: 15)).foregroundStyle(OB.muted)
        }
    }

    private var welcome: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                (Text("Talk less.\n") + Text("Point more.").foregroundColor(OB.loop))
                    .font(.system(size: 40, weight: .heavy)).tracking(-1.2).lineSpacing(-4)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Hold a key, talk, and circle what you mean.")
                    .font(.system(size: 16)).foregroundStyle(OB.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 270, alignment: .leading)
            LoopingVideo(name: "onboarding-demo")
                .frame(width: 330, height: 312)
                .background(OB.panel)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxHeight: .infinity)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading("Three permissions", "Your voice stays on this Mac.")
            VStack(spacing: 0) {
                permRow("Accessibility", "Notice the key, and paste for you", model.perms.accessibility, model.allowAccessibility)
                Rectangle().fill(OB.line).frame(height: 1)
                permRow("Microphone", "Hear you while the key is held", model.perms.microphone, model.allowMicrophone)
                Rectangle().fill(OB.line).frame(height: 1)
                permRow("Screen Recording", "Take the screenshot when you circle", model.perms.screen, model.allowScreen)
            }
        }
        .padding(.horizontal, 24)
    }

    private func permRow(_ name: String, _ detail: String, _ granted: Bool, _ allow: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22)).foregroundStyle(granted ? OB.green : OB.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 17, weight: .bold))
                Text(detail).font(.system(size: 14)).foregroundStyle(OB.muted)
            }
            Spacer()
            if granted {
                Text("Granted").font(.system(size: 14, weight: .bold)).foregroundStyle(OB.green)
            } else {
                Button("Allow", action: allow).buttonStyle(PrimaryButton())
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 16)
    }

    private var keycap: some View {
        Text(model.key.capLabel)
            .font(.system(size: 15, weight: .bold))
            .frame(width: 104, height: 80, alignment: .bottomLeading)
            .padding(.init(top: 0, leading: 12, bottom: 10, trailing: 0))
            .frame(width: 104, height: 80)
            .background(RoundedRectangle(cornerRadius: 13).fill(OB.raised))
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 13).fill(OB.panel).frame(height: 5).offset(y: 5).mask(Rectangle())
            }
    }

    private var talk: some View {
        VStack(alignment: .leading, spacing: 32) {
            heading("Hold the key and talk", "Hold \(model.key.name), say anything, then let go.")
            HStack(alignment: .center, spacing: 28) {
                keycap
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your words appear here").font(.system(size: 13)).foregroundStyle(OB.muted)
                    Text(model.said.isEmpty ? " " : model.said)
                        .font(.system(size: 18)).lineLimit(3)
                        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                        .padding(.init(top: 16, leading: 18, bottom: 16, trailing: 18))
                        .background(RoundedRectangle(cornerRadius: 14).fill(OB.panel))
                }
            }
            if !model.said.isEmpty {
                success("That's dictation. It works in any app.")
            } else if !model.perms.accessibility || !model.perms.microphone {
                Text("Point needs Accessibility and Microphone first. Go back to allow them.")
                    .font(.system(size: 14)).foregroundStyle(OB.muted)
            }
        }
        .padding(.horizontal, 24)
    }

    private var circle: some View {
        VStack(alignment: .leading, spacing: 28) {
            heading("Now circle while you talk", "Hold \(model.key.name), say \"make this one green\", and circle Pay now.")
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Checkout").font(.system(size: 15, weight: .heavy))
                    HStack { Text("Pro plan, yearly"); Spacer(); Text("$96.00").bold() }.font(.system(size: 14))
                    HStack(spacing: 10) {
                        Text("Back").font(.system(size: 14, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.89)))
                        Text("Pay now").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.14, green: 0.34, blue: 0.9)))
                    }
                    .padding(.top, 14)
                }
                .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.17))
                .padding(.init(top: 20, leading: 22, bottom: 24, trailing: 22))
                .frame(width: 290, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.953, green: 0.961, blue: 0.973)))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your agent gets").font(.system(size: 13)).foregroundStyle(OB.muted)
                    Text(model.circled.map { $0.isEmpty ? "(no words, just the circle)" : "\"\($0)\"" } ?? "\"Make this one green.\"")
                        .font(.system(size: 20, weight: .bold)).lineLimit(3)
                        .foregroundStyle(model.circled == nil ? OB.muted : OB.ink)
                    Text("plus a screenshot with your circle on it").font(.system(size: 15)).foregroundStyle(OB.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.circled != nil {
                success("Got your words and your circle.")
            } else if model.circleHint {
                Text("That was dictation only. Try again, and draw a loop while you hold the key.")
                    .font(.system(size: 14)).foregroundStyle(OB.muted)
            } else if !model.perms.screen {
                Text("The screenshot needs Screen Recording. macOS will ask the first time.")
                    .font(.system(size: 14)).foregroundStyle(OB.muted)
            }
        }
        .padding(.horizontal, 24)
    }

    private func success(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
            Text(text).font(.system(size: 15, weight: .bold))
        }
        .foregroundStyle(OB.green)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("You're set", "Point lives in your menu bar.")
            VStack(spacing: 0) {
                tip("Hold \(model.key.name), talk", "Dictation, wherever your cursor is")
                Rectangle().fill(OB.line).frame(height: 1)
                tip("Keep holding, circle", "Adds a screenshot with your mark")
                Rectangle().fill(OB.line).frame(height: 1)
                tip("Tap Space while holding", "Hands-free until you press the key again")
                Rectangle().fill(OB.line).frame(height: 1)
                tip("Double-tap the key", "A floating sticky pad")
            }
            Toggle(isOn: Binding(get: { model.launchAtLogin },
                                 set: { _ in model.launchAtLogin = LoginItem.toggle() })) {
                Text("Open Point when I log in").font(.system(size: 15))
            }
            .toggleStyle(.checkbox)
            Button("Something not working? Send feedback…") { FeedbackController.shared.show() }
                .buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(OB.muted).underline()
        }
        .padding(.horizontal, 24)
    }

    private func tip(_ what: String, _ result: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(what).font(.system(size: 16, weight: .bold)).frame(width: 230, alignment: .leading)
            Text(result).font(.system(size: 15)).foregroundStyle(OB.muted)
            Spacer()
        }
        .padding(.vertical, 13)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(i == model.step ? OB.loop : OB.dot)
                        .frame(width: i == model.step ? 22 : 6, height: 6)
                }
            }
            .accessibilityLabel("Step \(model.step + 1) of 5")
            Spacer()
            if model.step > 0 && model.step < 4 {
                Button("Back") { model.step -= 1 }.buttonStyle(QuietButton())
            }
            if model.step == 4 {
                Menu("Change the key") {
                    ForEach(TriggerKey.allCases, id: \.self) { k in
                        Button(k.menuTitle) { TriggerKey.current = k; model.key = k }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
                .foregroundStyle(OB.muted).padding(.trailing, 6)
                Button("Start using Point") { model.onFinish() }.buttonStyle(PrimaryButton())
            } else {
                Button(model.step == 0 ? "Get started" : "Continue") { model.step += 1 }
                    .buttonStyle(PrimaryButton())
            }
        }
    }
}

// ─── Looping, silent video ───────────────────────────────────────────────────

private struct LoopingVideo: NSViewRepresentable {
    let name: String

    final class PlayerView: NSView {
        var looper: AVPlayerLooper?
        let player = AVQueuePlayer()
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        if let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
            view.looper = AVPlayerLooper(player: view.player, templateItem: AVPlayerItem(url: url))
            view.player.isMuted = true
            view.player.play()
        }
        return view
    }

    func updateNSView(_ nsView: PlayerView, context: Context) {}
}
