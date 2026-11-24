// The "AI agents" UI: a section in Settings, and the Connect-your-agents step in the welcome.
// The work itself is in Agents.swift.

import SwiftUI

final class AgentsModel: ObservableObject {
    @Published var statuses: [AgentStatus] = []
    @Published var selected: Set<AgentID> = []
    @Published var busy = false
    @Published var error: String?
    @Published var connectedNow = false

    init() { refresh(preselect: true) }

    var installed: [AgentStatus] { statuses.filter(\.installed) }
    var toConnect: [AgentID] { installed.filter { !$0.connected && selected.contains($0.id) }.map(\.id) }

    func refresh(preselect: Bool = false) {
        statuses = Agents.statuses()
        if preselect { selected = Set(statuses.filter { $0.installed && !$0.connected }.map(\.id)) }
    }

    func connect(_ ids: [AgentID], then done: (() -> Void)? = nil) {
        run(ids, { try Agents.connect($0) }) { ok in
            if ok { self.connectedNow = true }
            done?()
        }
    }

    func disconnect(_ id: AgentID) { run([id], { try Agents.disconnect($0) }) { _ in } }

    private func run(_ ids: [AgentID], _ op: @escaping (AgentID) throws -> Void, done: @escaping (Bool) -> Void) {
        guard !ids.isEmpty else { done(true); return }
        busy = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            var problems: [String] = []
            for id in ids {
                do { try op(id) } catch { problems.append("\(Agents.name(id)): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async {
                self.busy = false
                self.error = problems.isEmpty ? nil : problems.joined(separator: "\n")
                self.refresh()
                done(problems.isEmpty)
            }
        }
    }
}

/// Settings → AI agents.
struct AgentsSettingsSection: View {
    @StateObject private var model = AgentsModel()

    var body: some View {
        Section {
            ForEach(model.statuses) { s in
                LabeledContent {
                    if !s.installed {
                        Text("Not found").foregroundStyle(.secondary)
                    } else if s.connected {
                        HStack(spacing: 10) {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon).foregroundStyle(.green)
                            Button("Disconnect") { model.disconnect(s.id) }.disabled(model.busy)
                        }
                    } else {
                        Button("Connect") { model.connect([s.id]) }.disabled(model.busy)
                    }
                } label: {
                    Text(s.name)
                }
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if model.connectedNow {
                Text("Restart any agent that was open so it picks up Point.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("AI agents")
        } footer: {
            Text("Connected agents can read your latest capture: your words and the screenshot with your mark. Point adds one entry named \u{201C}point\u{201D} to each agent\u{2019}s settings and keeps a backup beside the file. Point still pastes into every app, connected or not.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { model.refresh() }
    }
}
