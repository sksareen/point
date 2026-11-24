// The Point window: a time machine of every capture, plus Settings.
// Opened from the menu bar (Open Point… / Settings…). SwiftUI hosted in an NSWindow.

import SwiftUI
import AVFoundation
import ServiceManagement
import UniformTypeIdentifiers

// ─── Model ───────────────────────────────────────────────────────────────────

struct Capture: Identifiable, Hashable {
    let id: Int
    let date: Date
    let kind: String              // "dictation" | "circle" | "circle_failed" | "note"
    let transcript: String
    let screenshot: URL?
    let audio: URL?
    let app: String?
    let timings: [String: Int]
    let metaURL: URL

    var icon: String {
        switch kind {
        case "circle": return "camera.viewfinder"
        case "circle_failed": return "exclamationmark.triangle"
        case "note": return "note.text"
        default: return "waveform"
        }
    }
}

struct DayGroup: Identifiable {
    let day: Date
    let items: [Capture]
    var id: Date { day }
}

final class CaptureStore: ObservableObject {
    static let shared = CaptureStore()
    /// Post on the main queue after writing a capture to refresh any open window.
    static let didChange = Notification.Name("PointCapturesChanged")

    @Published private(set) var captures: [Capture] = []

    private init() {
        NotificationCenter.default.addObserver(forName: Self.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        let dir = CAPTURES_DIR
        DispatchQueue.global(qos: .userInitiated).async {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let iso = ISO8601DateFormatter()
            var out: [Capture] = []
            for f in files where f.pathExtension == "json" {
                guard let data = try? Data(contentsOf: f),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let id = (obj["id"] as? NSNumber)?.intValue ?? 0
                let date = (obj["created_at"] as? String).flatMap(iso.date(from:))
                    ?? Date(timeIntervalSince1970: Double(id) / 1000)
                let shot = Self.resolve(obj["screenshot"] as? String, in: dir)
                let audio = Self.resolve(obj["audio"] as? String, in: dir)
                out.append(Capture(
                    id: id, date: date,
                    kind: (obj["kind"] as? String) ?? (shot != nil ? "circle" : "dictation"),
                    transcript: (obj["transcript"] as? String) ?? "",
                    screenshot: shot, audio: audio,
                    app: obj["app"] as? String,
                    timings: (obj["timings_ms"] as? [String: Int]) ?? [:],
                    metaURL: f))
            }
            out.sort { $0.date > $1.date }
            DispatchQueue.main.async { self.captures = out }
        }
    }

    /// Prefer the copy inside Point's captures folder (older entries were migrated
    /// from another location and still reference their original paths).
    private static func resolve(_ path: String?, in dir: URL) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let name = (path as NSString).lastPathComponent.replacingOccurrences(of: "sauron_circle_", with: "point_")
        let local = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    /// Moves a capture's files to the Trash (recoverable).
    func trash(_ c: Capture) {
        for url in [c.metaURL, c.screenshot, c.audio].compactMap({ $0 })
        where url.path.hasPrefix(CAPTURES_DIR.path) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        reload()
    }
}

// ─── Window ──────────────────────────────────────────────────────────────────

enum PointTab: Hashable { case captures, settings }

final class WindowModel: ObservableObject {
    @Published var tab: PointTab = .captures
}

final class PointWindowController {
    static let shared = PointWindowController()
    private var window: NSWindow?
    private let model = WindowModel()

    func show(_ tab: PointTab) {
        model.tab = tab
        if window == nil {
            let root = PointRootView()
                .environmentObject(model)
                .environmentObject(CaptureStore.shared)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Point"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 1000, height: 660))
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("PointMainWindow")
            window = w
        }
        CaptureStore.shared.reload()
        AppPresence.windowWillShow()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PointRootView: View {
    @EnvironmentObject var model: WindowModel

    var body: some View {
        TabView(selection: $model.tab) {
            CapturesView()
                .tabItem { Label("Captures", systemImage: "clock.arrow.circlepath") }
                .tag(PointTab.captures)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(PointTab.settings)
        }
        .frame(minWidth: 780, minHeight: 480)
    }
}

// ─── Captures (time machine) ─────────────────────────────────────────────────

private enum KindFilter: String, CaseIterable, Identifiable {
    case all = "All", screenshots = "Screenshots", dictation = "Dictation"
    var id: String { rawValue }
}

struct CapturesView: View {
    @EnvironmentObject var store: CaptureStore
    @State private var selection: Capture.ID?
    @State private var query = ""
    @State private var filter: KindFilter = .all

    private var filtered: [Capture] {
        store.captures.filter { c in
            switch filter {
            case .all: break
            case .screenshots: if c.screenshot == nil { return false }
            case .dictation: if c.screenshot != nil { return false }
            }
            return query.isEmpty
                || c.transcript.localizedCaseInsensitiveContains(query)
                || (c.app ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var groups: [DayGroup] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { DayGroup(day: $0, items: byDay[$0] ?? []) }
    }

    private var selected: Capture? { store.captures.first { $0.id == selection } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    TextField("Search what you said, or an app", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $filter) {
                        ForEach(KindFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(10)

                List(selection: $selection) {
                    ForEach(groups) { group in
                        Section(dayTitle(group.day)) {
                            ForEach(group.items) { c in
                                CaptureRow(capture: c)
                                    .tag(c.id)
                                    .contextMenu { contextMenu(for: c) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView(
                            store.captures.isEmpty ? "No captures yet" : "No matches",
                            systemImage: "hand.point.up.left",
                            description: Text(store.captures.isEmpty
                                ? "Hold \(TriggerKey.current.symbol) and talk. Draw a loop to add a screenshot."
                                : "Try a different search or filter."))
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 520)

            Group {
                if let c = selected {
                    CaptureDetail(capture: c)
                } else {
                    ContentUnavailableView("Select a capture", systemImage: "clock.arrow.circlepath",
                                           description: Text("Use ↑ ↓ to move through time."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selection == nil { selection = filtered.first?.id } }
        .onChange(of: store.captures) { _, new in
            if let s = selection, !new.contains(where: { $0.id == s }) { selection = new.first?.id }
        }
    }

    @ViewBuilder
    private func contextMenu(for c: Capture) -> some View {
        Button("Copy Transcript") { copy(c.transcript) }
        if let shot = c.screenshot {
            Button("Copy Screenshot Path") { copy(shot.path) }
            Button("Open Screenshot") { NSWorkspace.shared.open(shot) }
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([c.screenshot ?? c.metaURL]) }
        Divider()
        Button("Move to Trash", role: .destructive) { store.trash(c) }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

struct CaptureRow: View {
    let capture: Capture

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: capture.icon)
                .foregroundStyle(capture.kind == "circle" ? Color.accentColor : .secondary)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(capture.transcript.isEmpty ? "(no speech)" : capture.transcript)
                    .lineLimit(2)
                    .foregroundStyle(capture.transcript.isEmpty ? .secondary : .primary)
                Text([capture.date.formatted(date: .omitted, time: .shortened), capture.app]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingURL: URL?
    private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playingURL == url { stop(); return }
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        p.play()
        player = p
        playingURL = url
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.stop() }
    }
}

struct CaptureDetail: View {
    let capture: Capture
    @StateObject private var audio = AudioPlayback()
    @State private var image: NSImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(capture.date.formatted(date: .complete, time: .standard))
                        .font(.title3.weight(.semibold))
                    if let app = capture.app {
                        Text("in \(app)").foregroundStyle(.secondary)
                    }
                }

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        .onDrag { capture.screenshot.map(screenshotDragProvider) ?? NSItemProvider() }
                        .onTapGesture { if let s = capture.screenshot { NSWorkspace.shared.open(s) } }
                        .help("Click to open full size. Drag to copy into another app.")
                } else if capture.kind == "circle_failed" {
                    Label("Screenshot failed (Screen Recording permission?)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                GroupBox {
                    Text(capture.transcript.isEmpty ? "(no speech recognized)" : capture.transcript)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }

                HStack(spacing: 10) {
                    if let url = capture.audio {
                        Button {
                            audio.toggle(url)
                        } label: {
                            Label(audio.playingURL == url ? "Stop" : "Play recording",
                                  systemImage: audio.playingURL == url ? "stop.fill" : "play.fill")
                        }
                    }
                    Button("Copy Transcript") { copy(capture.transcript) }
                        .disabled(capture.transcript.isEmpty)
                    if let shot = capture.screenshot {
                        Button("Copy as Pasted") { copy(capture.transcript + "\n\n[Screenshot: \(shot.path)]") }
                    }
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([capture.screenshot ?? capture.metaURL])
                    }
                }

                if !timingSummary.isEmpty {
                    Text(timingSummary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .task(id: capture.id) {
            audio.stop()
            image = nil
            guard let url = capture.screenshot else { return }
            image = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
        }
        .onDisappear { audio.stop() }
    }

    private var timingSummary: String {
        let t = capture.timings
        var parts: [String] = []
        if let mic = t["mic_first_audio"] { parts.append("mic live \(mic) ms") }
        if let up = t["key_up"] {
            parts.append(String(format: "held %.1f s", Double(up) / 1000))
            if let pasted = t["pasted"] { parts.append("release → paste \(pasted - up) ms") }
        }
        return parts.joined(separator: " · ")
    }
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Drag provider for a screenshot. Offers the PNG as image data (web chats and
/// rich-text fields take the image itself) and as a file (Finder and file drops).
private func screenshotDragProvider(_ url: URL) -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = url.deletingPathExtension().lastPathComponent
    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
        completion(try? Data(contentsOf: url), nil)
        return nil
    }
    provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
        completion(url, false, nil)
        return nil
    }
    return provider
}

// ─── Settings ────────────────────────────────────────────────────────────────

struct SettingsView: View {
    @EnvironmentObject var store: CaptureStore
    @State private var trigger = TriggerKey.current
    @State private var markStyle = MarkStyle.current
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var vocab = ""
    @State private var vocabSaved = true
    @State private var perms = PermissionStatus.current()
    @State private var capturesPath = CAPTURES_DIR.path

    private var vocabURL: URL { POINT_DIR.appendingPathComponent("vocab.txt") }

    private func chooseCapturesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = CAPTURES_DIR
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        CapturesFolder.set(url)
        capturesPath = url.path
        store.reload()
    }

    var body: some View {
        Form {
            Section("Trigger") {
                Picker("Trigger key", selection: $trigger) {
                    ForEach(TriggerKey.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
                }
                .onChange(of: trigger) { _, new in TriggerKey.current = new }
                Picker("Mark", selection: $markStyle) {
                    ForEach(MarkStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: markStyle) { _, new in MarkStyle.current = new }
                Text("Hold to talk · mark the screen while holding to add a screenshot · double-tap for the sticky pad.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, want in
                        if want != LoginItem.isEnabled { launchAtLogin = LoginItem.toggle() }
                    }
                LabeledContent("Welcome walkthrough") {
                    Button("Show again") { OnboardingController.shared.show() }
                }
                LabeledContent("Something broken or missing?") {
                    Button("Send feedback…") { FeedbackController.shared.show() }
                }
            }

            Section("Permissions") {
                PermissionRow(name: "Accessibility", detail: "to notice the trigger key",
                              granted: perms.accessibility, pane: "Privacy_Accessibility")
                PermissionRow(name: "Microphone", detail: "to hear you",
                              granted: perms.microphone, pane: "Privacy_Microphone")
                PermissionRow(name: "Screen Recording", detail: "for screenshots when you draw",
                              granted: perms.screen, pane: "Privacy_ScreenCapture")
                Button("Re-check") { perms = PermissionStatus.current() }
            }

            Section("Vocabulary") {
                TextEditor(text: $vocab)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .onChange(of: vocab) { _, _ in vocabSaved = false }
                HStack {
                    Text("Names and jargon to recognize, one per line. Used from your next recording.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(vocabSaved ? "Saved" : "Save") { saveVocab() }
                        .disabled(vocabSaved)
                }
            }

            Section("Storage") {
                LabeledContent("Captures", value: "\(store.captures.count)")
                LabeledContent("Captures folder") {
                    Text((capturesPath as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button("Change…") { chooseCapturesFolder() }
                    if CapturesFolder.isCustom {
                        Button("Use Default") {
                            CapturesFolder.set(nil)
                            capturesPath = CAPTURES_DIR.path
                            store.reload()
                        }
                    }
                    Spacer()
                    Button("Open Folder") {
                        try? FileManager.default.createDirectory(at: CAPTURES_DIR, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(CAPTURES_DIR)
                    }
                }
                Text("New captures are saved here. Captures already in the old folder stay there.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: APP_VERSION)
                Link("github.com/sksareen/point", destination: URL(string: "https://github.com/sksareen/point")!)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: MarkStyle.changed)) { _ in
            markStyle = MarkStyle.current
        }
        .onAppear {
            trigger = TriggerKey.current
            markStyle = MarkStyle.current
            launchAtLogin = LoginItem.isEnabled
            perms = PermissionStatus.current()
            vocab = (try? String(contentsOf: vocabURL, encoding: .utf8)) ?? ""
            vocabSaved = true
        }
    }

    private func saveVocab() {
        try? FileManager.default.createDirectory(at: POINT_DIR, withIntermediateDirectories: true)
        try? vocab.write(to: vocabURL, atomically: true, encoding: .utf8)
        vocabSaved = true
    }
}

struct PermissionStatus {
    var accessibility: Bool
    var microphone: Bool
    var screen: Bool

    static func current() -> PermissionStatus {
        PermissionStatus(
            accessibility: AXIsProcessTrusted(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            screen: CGPreflightScreenCaptureAccess())
    }
}

struct PermissionRow: View {
    let name: String
    let detail: String
    let granted: Bool
    let pane: String

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        }
    }
}
