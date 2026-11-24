// Send feedback: a small window with one text box (dictate into it with Point), an optional
// "attach my last capture" preview, and Send. This is the only place Point talks to the network,
// and only when the user presses Send. The audio recording is never sent.

import SwiftUI

let FEEDBACK_URL = URL(string: "https://www.pointandtell.app/api/feedback")!

final class FeedbackController: NSObject, NSWindowDelegate {
    static let shared = FeedbackController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let model = FeedbackModel(onClose: { [weak self] in self?.window?.close() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: FeedbackView(model: model)))
            w.title = "Send feedback"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(FB.bg)
            w.setContentSize(NSSize(width: 520, height: 600))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        AppPresence.windowWillShow()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}

private enum FB {
    static let bg = Color(red: 0.102, green: 0.129, blue: 0.165)
    static let panel = Color(red: 0.063, green: 0.086, blue: 0.114)
    static let raised = Color(red: 0.145, green: 0.180, blue: 0.224)
    static let ink = Color(red: 0.902, green: 0.925, blue: 0.949)
    static let muted = Color(red: 0.592, green: 0.647, blue: 0.706)
    static let red = Color(red: 0.898, green: 0.212, blue: 0.290)
    static let green = Color(red: 0.373, green: 0.831, blue: 0.596)
}

/// The newest capture on disk, read straight from its JSON (ids are timestamps, so names sort).
private struct LastCapture {
    let meta: [String: Any]
    let screenshot: URL?
    let date: Date?

    var transcript: String { (meta["transcript"] as? String) ?? "" }
    var app: String { (meta["app"] as? String) ?? "" }
    var timings: [String: Int] {
        ((meta["timings_ms"] as? [String: Any]) ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue }
    }

    static func load() -> LastCapture? {
        let dir = CAPTURES_DIR
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("point_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for f in files.prefix(5) {
            guard let data = try? Data(contentsOf: f),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            var shot: URL?
            if let p = obj["screenshot"] as? String, !p.isEmpty {
                let local = dir.appendingPathComponent((p as NSString).lastPathComponent)
                if FileManager.default.fileExists(atPath: local.path) { shot = local }
            }
            let date = (obj["created_at"] as? String).flatMap(ISO8601DateFormatter().date(from:))
            return LastCapture(meta: obj, screenshot: shot, date: date)
        }
        return nil
    }

    /// The screenshot shrunk to at most 1600 px wide, as JPEG, so it fits in one request.
    func screenshotJPEG() -> Data? {
        guard let screenshot, let img = NSImage(contentsOf: screenshot),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, 1600 / CGFloat(cg.width))
        let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }
}

final class FeedbackModel: ObservableObject {
    enum Phase: Equatable { case writing, sending, sent, failed(String) }

    @Published var message = ""
    @Published var email = ""
    @Published var phase: Phase = .writing
    @Published var attached = false
    @Published var includeScreenshot = true
    fileprivate let last = LastCapture.load()
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) { self.onClose = onClose }

    var canSend: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .sending }

    var lastAge: String {
        guard let d = last?.date else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    var timingLine: String {
        guard let t = last?.timings else { return "" }
        var parts: [String] = []
        if let mic = t["mic_first_audio"] { parts.append("Mic started in \(mic) ms") }
        if let up = t["key_up"], let pasted = t["pasted"], pasted >= up {
            parts.append(String(format: "pasted in %.1f s", Double(pasted - up) / 1000))
        }
        return parts.joined(separator: " · ")
    }

    func send() {
        guard canSend else { return }
        phase = .sending
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var body: [String: Any] = [
            "message": message,
            "app_version": APP_VERSION,
            "os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "trigger_key": TriggerKey.current.name,
        ]
        let mail = email.trimmingCharacters(in: .whitespaces)
        if !mail.isEmpty { body["email"] = mail }
        let last = self.last, attach = attached, withShot = includeScreenshot

        DispatchQueue.global(qos: .userInitiated).async {
            if attach, let last {
                var cap: [String: Any] = [:]
                for key in ["transcript", "app", "kind", "created_at", "engine", "locale", "audio_seconds", "timings_ms"] {
                    if let v = last.meta[key], !(v is NSNull) { cap[key] = v }
                }
                body["capture"] = cap
                if withShot, let jpeg = last.screenshotJPEG() { body["screenshot"] = jpeg.base64EncodedString() }
            }
            var req = URLRequest(url: FEEDBACK_URL)
            req.httpMethod = "POST"
            req.timeoutInterval = 30
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("point-app", forHTTPHeaderField: "X-Point-Client")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: req) { _, response, error in
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async {
                    if error == nil && code == 200 {
                        self.phase = .sent
                    } else if error != nil {
                        self.phase = .failed("Couldn't reach the server. Check your connection and try again.")
                    } else {
                        self.phase = .failed("Couldn't send (error \(code)). Your message is still here; try again in a bit.")
                    }
                }
            }.resume()
        }
    }
}

struct FeedbackView: View {
    @ObservedObject var model: FeedbackModel
    @FocusState private var messageFocused: Bool

    var body: some View {
        Group {
            if model.phase == .sent { sent } else { form }
        }
        .frame(width: 520, height: 600)
        .background(FB.bg)
        .foregroundStyle(FB.ink)
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Send feedback").font(.system(size: 26, weight: .heavy)).tracking(-0.5)
                Text("What's broken, missing, or annoying? Hold \(TriggerKey.current.name) to say it.")
                    .font(.system(size: 15)).foregroundStyle(FB.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Your message").font(.system(size: 13)).foregroundStyle(FB.muted)
                TextEditor(text: $model.message)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .focused($messageFocused)
                    .padding(.init(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14).fill(FB.panel))
            }
            .frame(maxHeight: .infinity)

            if model.last != nil {
                if model.attached { attachment } else { attachButton }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Email, if you'd like a reply (optional)").font(.system(size: 13)).foregroundStyle(FB.muted)
                TextField("you@example.com", text: $model.email)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(FB.panel))
            }

            if case .failed(let why) = model.phase {
                Text(why).font(.system(size: 13)).foregroundStyle(FB.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 16) {
                Text(model.attached ? "Sends what you see here. Never the audio."
                                    : "Sends your message and Point's version. Nothing else.")
                    .font(.system(size: 12.5)).foregroundStyle(FB.muted)
                Spacer()
                Button(model.phase == .sending ? "Sending…" : "Send") { model.send() }
                    .buttonStyle(FBPrimary(enabled: model.canSend))
                    .disabled(!model.canSend)
            }
        }
        .padding(.init(top: 44, leading: 40, bottom: 28, trailing: 40))
        .onAppear { messageFocused = true }
    }

    private var attachButton: some View {
        Button { model.attached = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                Text("Attach my last capture").font(.system(size: 15, weight: .medium))
                Spacer()
                Text(model.lastAge).font(.system(size: 13)).foregroundStyle(FB.muted)
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 12).fill(FB.raised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var attachment: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Attached: your last capture").font(.system(size: 14, weight: .bold))
                Spacer()
                Button("Remove") { model.attached = false }
                    .buttonStyle(.plain).font(.system(size: 14, weight: .medium)).foregroundStyle(FB.muted)
                    .frame(minHeight: 30)
            }
            HStack(alignment: .top, spacing: 14) {
                if let shot = model.last?.screenshot, model.includeScreenshot, let img = NSImage(contentsOf: shot) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 132, height: 84).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 5) {
                    let heard = model.last?.transcript ?? ""
                    Text(heard.isEmpty ? "(no words)" : "\"\(heard)\"").font(.system(size: 13.5)).lineLimit(3)
                    Text([model.last?.app.isEmpty == false ? "In \(model.last!.app)" : "", model.lastAge]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(FB.muted)
                    if !model.timingLine.isEmpty {
                        Text(model.timingLine).font(.system(size: 13)).foregroundStyle(FB.muted)
                    }
                }
            }
            if model.last?.screenshot != nil {
                Toggle(isOn: $model.includeScreenshot) {
                    (Text("Include the screenshot ") + Text("(your whole screen)").foregroundColor(FB.muted))
                        .font(.system(size: 14))
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
        .background(RoundedRectangle(cornerRadius: 14).fill(FB.panel))
    }

    private var sent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(FB.green)
            Text("Sent. Thank you.").font(.system(size: 26, weight: .heavy)).tracking(-0.5)
            Text("A person reads every one of these. If you left an email, you'll hear back.")
                .font(.system(size: 15)).foregroundStyle(FB.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
            Button("Close") { model.onClose() }.buttonStyle(FBQuiet()).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FBPrimary: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(enabled ? Color.white : FB.muted)
            .padding(.horizontal, 26).frame(minHeight: 44)
            .background(Capsule().fill(enabled ? FB.red : FB.raised))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct FBQuiet: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold)).foregroundStyle(FB.ink)
            .padding(.horizontal, 26).frame(minHeight: 44)
            .background(Capsule().fill(FB.raised))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
