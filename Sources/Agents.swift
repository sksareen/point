// Connect AI agents on this Mac to Point's tool server (MCP.swift), so they can read the user's
// latest capture. Each agent gets one entry named "point" in its own config; nothing else in those
// files changes, and a one-time backup sits beside each file (`<file>.point-backup`).
// Disconnect removes only that entry. Nothing is written until the user connects an agent.

import Foundation

enum AgentID: String, CaseIterable, Identifiable {
    case claudeCode, claudeDesktop, cursor, codex, gemini, opencode
    var id: String { rawValue }
}

struct AgentStatus: Identifiable, Equatable {
    let id: AgentID
    let name: String
    let installed: Bool
    let connected: Bool
}

enum AgentConnectError: LocalizedError {
    case unreadable(String)
    case cliMissing(String)
    case cliFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let f): return "Couldn't read \(f) (it may contain comments). Left it unchanged."
        case .cliMissing(let t): return "Couldn't find the \(t) command."
        case .cliFailed(let m): return m
        }
    }
}

enum Agents {
    static let entryName = "point"
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// What each agent runs. Agents start it themselves; Point doesn't need to be open.
    static var command: String {
        Bundle.main.executablePath ?? "/Applications/Point.app/Contents/MacOS/Point"
    }
    static let args = ["--mcp"]

    static func name(_ id: AgentID) -> String {
        switch id {
        case .claudeCode: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .opencode: return "opencode"
        }
    }

    // ─── Where each agent keeps its config ───────────────────────────────────

    private static func path(_ rel: String) -> URL { home.appendingPathComponent(rel) }
    private static var claudeDesktopConfig: URL { path("Library/Application Support/Claude/claude_desktop_config.json") }
    private static var cursorConfig: URL { path(".cursor/mcp.json") }
    private static var geminiConfig: URL { path(".gemini/settings.json") }
    private static var codexConfig: URL { path(".codex/config.toml") }
    private static var opencodeConfig: URL { path(".config/opencode/opencode.json") }
    private static var claudeCodeState: URL { path(".claude.json") }

    private static func exists(_ p: String) -> Bool { FileManager.default.fileExists(atPath: p) }

    static func installed(_ id: AgentID) -> Bool {
        switch id {
        case .claudeCode: return claudeBinary != nil
        case .claudeDesktop: return exists("/Applications/Claude.app")
        case .cursor: return exists("/Applications/Cursor.app") || exists(path(".cursor").path)
        case .codex: return exists(path(".codex").path)
        case .gemini: return exists(path(".gemini").path)
        case .opencode: return exists(path(".config/opencode").path) || exists(path(".opencode/bin/opencode").path)
        }
    }

    static func connected(_ id: AgentID) -> Bool {
        switch id {
        case .claudeCode: return (readJSON(claudeCodeState)?["mcpServers"] as? [String: Any])?[entryName] != nil
        case .claudeDesktop: return hasEntry(claudeDesktopConfig, key: "mcpServers")
        case .cursor: return hasEntry(cursorConfig, key: "mcpServers")
        case .gemini: return hasEntry(geminiConfig, key: "mcpServers")
        case .opencode: return hasEntry(opencodeConfig, key: "mcp")
        case .codex:
            let text = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
            return text.contains(tomlStart) || text.contains("[mcp_servers.\(entryName)]")
        }
    }

    static func statuses() -> [AgentStatus] {
        AgentID.allCases.map { AgentStatus(id: $0, name: name($0), installed: installed($0), connected: connected($0)) }
    }

    // ─── Connect / disconnect ─────────────────────────────────────────────────

    static func connect(_ id: AgentID) throws {
        let std: [String: Any] = ["command": command, "args": args]
        switch id {
        case .claudeCode:
            _ = try? runClaude(["mcp", "remove", "--scope", "user", entryName])
            try runClaude(["mcp", "add", "--scope", "user", entryName, "--", command] + args)
        case .claudeDesktop: try setEntry(claudeDesktopConfig, key: "mcpServers", value: std)
        case .cursor: try setEntry(cursorConfig, key: "mcpServers", value: std)
        case .gemini: try setEntry(geminiConfig, key: "mcpServers", value: std)
        case .opencode:
            try setEntry(opencodeConfig, key: "mcp",
                         value: ["type": "local", "command": [command] + args, "enabled": true],
                         schema: "https://opencode.ai/config.json")
        case .codex: try setTOMLBlock()
        }
    }

    static func disconnect(_ id: AgentID) throws {
        switch id {
        case .claudeCode: try runClaude(["mcp", "remove", "--scope", "user", entryName])
        case .claudeDesktop: try removeEntry(claudeDesktopConfig, key: "mcpServers")
        case .cursor: try removeEntry(cursorConfig, key: "mcpServers")
        case .gemini: try removeEntry(geminiConfig, key: "mcpServers")
        case .opencode: try removeEntry(opencodeConfig, key: "mcp")
        case .codex: try removeTOMLBlock()
        }
    }

    /// If Point moved since an agent was connected, point that agent at the new location.
    static func refreshMovedEntries() {
        for id in AgentID.allCases where connected(id) && !entryMatchesCurrentPath(id) {
            try? connect(id)
        }
    }

    private static func entryMatchesCurrentPath(_ id: AgentID) -> Bool {
        switch id {
        case .claudeCode:
            let e = (readJSON(claudeCodeState)?["mcpServers"] as? [String: Any])?[entryName] as? [String: Any]
            return (e?["command"] as? String) == command
        case .claudeDesktop, .cursor, .gemini:
            let file = id == .claudeDesktop ? claudeDesktopConfig : id == .cursor ? cursorConfig : geminiConfig
            let e = (readJSON(file)?["mcpServers"] as? [String: Any])?[entryName] as? [String: Any]
            return (e?["command"] as? String) == command
        case .opencode:
            let e = (readJSON(opencodeConfig)?["mcp"] as? [String: Any])?[entryName] as? [String: Any]
            return (e?["command"] as? [String])?.first == command
        case .codex:
            return ((try? String(contentsOf: codexConfig, encoding: .utf8)) ?? "").contains("command = \(tomlString(command))")
        }
    }

    // ─── JSON configs ─────────────────────────────────────────────────────────

    private static func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func hasEntry(_ url: URL, key: String) -> Bool {
        (readJSON(url)?[key] as? [String: Any])?[entryName] != nil
    }

    private static func backup(_ url: URL) {
        let b = url.appendingPathExtension("point-backup")
        if FileManager.default.fileExists(atPath: url.path) && !FileManager.default.fileExists(atPath: b.path) {
            try? FileManager.default.copyItem(at: url, to: b)
        }
    }

    /// Read-modify-write one JSON config. Refuses to touch a file it can't parse.
    private static func editJSON(_ url: URL, schema: String? = nil, _ change: (inout [String: Any]) -> Void) throws {
        var obj: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AgentConnectError.unreadable(url.path.replacingOccurrences(of: home.path, with: "~"))
            }
            obj = parsed
            backup(url)
        } else if let schema {
            obj["$schema"] = schema
        }
        change(&obj)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
        try out.write(to: url, options: .atomic)
    }

    private static func setEntry(_ url: URL, key: String, value: [String: Any], schema: String? = nil) throws {
        try editJSON(url, schema: schema) { obj in
            var servers = obj[key] as? [String: Any] ?? [:]
            servers[entryName] = value
            obj[key] = servers
        }
    }

    private static func removeEntry(_ url: URL, key: String) throws {
        guard hasEntry(url, key: key) else { return }
        try editJSON(url) { obj in
            var servers = obj[key] as? [String: Any] ?? [:]
            servers[entryName] = nil
            obj[key] = servers
        }
    }

    // ─── Codex (TOML): one marked block at the end of config.toml ─────────────

    private static let tomlStart = "# point:start"
    private static let tomlEnd = "# point:end"

    private static func tomlString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func withoutBlock(_ text: String) -> String {
        guard let a = text.range(of: tomlStart), let b = text.range(of: tomlEnd, range: a.upperBound..<text.endIndex) else {
            return text
        }
        var end = b.upperBound
        if end < text.endIndex, text[end] == "\n" { end = text.index(after: end) }
        var start = a.lowerBound
        if start > text.startIndex, text[text.index(before: start)] == "\n",
           start > text.index(after: text.startIndex), text[text.index(start, offsetBy: -2)] == "\n" {
            start = text.index(before: start)  // also drop the blank line we added before the block
        }
        return String(text[..<start]) + String(text[end...])
    }

    private static func setTOMLBlock() throws {
        let text = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
        if text.contains("[mcp_servers.\(entryName)]") && !text.contains(tomlStart) {
            throw AgentConnectError.cliFailed("Codex already has a server named \"point\" that Point didn't add. Left it unchanged.")
        }
        backup(codexConfig)
        var base = withoutBlock(text)
        if !base.isEmpty && !base.hasSuffix("\n") { base += "\n" }
        let block = """
            \(tomlStart)
            [mcp_servers.\(entryName)]
            command = \(tomlString(command))
            args = [\(args.map(tomlString).joined(separator: ", "))]
            \(tomlEnd)

            """
        try FileManager.default.createDirectory(at: codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (base + (base.isEmpty ? "" : "\n") + block).write(to: codexConfig, atomically: true, encoding: .utf8)
    }

    private static func removeTOMLBlock() throws {
        guard let text = try? String(contentsOf: codexConfig, encoding: .utf8), text.contains(tomlStart) else { return }
        try withoutBlock(text).write(to: codexConfig, atomically: true, encoding: .utf8)
    }

    // ─── Claude Code: through its own CLI, which owns ~/.claude.json ──────────

    static var claudeBinary: String? {
        let candidates = [
            path(".local/bin/claude").path, path(".claude/local/claude").path,
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    private static func runClaude(_ arguments: [String]) throws -> String {
        guard let bin = claudeBinary else { throw AgentConnectError.cliMissing("claude") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw AgentConnectError.cliFailed("claude \(arguments.prefix(2).joined(separator: " ")) failed: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return text
    }

    // ─── Command line, for testing: Point --agents [status | connect <id> | disconnect <id>] ──

    static func cli(_ argv: [String]) -> Never {
        func line(_ s: AgentStatus) -> String {
            "\(s.id.rawValue)\t\(s.installed ? "installed" : "not installed")\t\(s.connected ? "connected" : "-")"
        }
        let cmd = argv.first ?? "status"
        if cmd == "status" {
            statuses().forEach { print(line($0)) }
            exit(0)
        }
        guard argv.count >= 2, let id = AgentID(rawValue: argv[1]), cmd == "connect" || cmd == "disconnect" else {
            print("usage: Point --agents [status | connect <id> | disconnect <id>]   ids: \(AgentID.allCases.map(\.rawValue).joined(separator: ", "))")
            exit(2)
        }
        do {
            if cmd == "connect" { try connect(id) } else { try disconnect(id) }
            print(line(AgentStatus(id: id, name: name(id), installed: installed(id), connected: connected(id))))
            exit(0)
        } catch {
            print("error: \(error.localizedDescription)")
            exit(1)
        }
    }
}
