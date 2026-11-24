// A small MCP server (JSON-RPC 2.0 over stdio) that lets AI agents read the user's Point captures.
// Agents launch it themselves as `Point.app/Contents/MacOS/Point --mcp`, so Point doesn't need to
// be running. It only reads capture files on this Mac and never touches the network.

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PointMCP {
    static let fallbackProtocol = "2025-06-18"

    static let instructions = """
        Point is a Mac app: the user holds a key, talks, and circles something on their screen. \
        Call last_capture when the user refers to something on their screen that you can't see \
        ("this", "here", "what I circled", "what I'm pointing at", "look at my screen", "my last capture"). \
        The red loop or rectangle on the screenshot marks what they mean.
        """

    static let tool: [String: Any] = [
        "name": "last_capture",
        "description": """
            The user's most recent Point captures: what they said while pointing at their screen, and a \
            screenshot with their red loop or rectangle marking what they mean. Use it when the user says \
            "this", "what I circled", "what I'm pointing at", or refers to something on screen you can't see. \
            Returns the newest capture with a screenshot unless asked otherwise.
            """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "count": [
                    "type": "integer", "minimum": 1, "maximum": 5,
                    "description": "How many recent captures to return, newest first. Default 1.",
                ],
                "include_dictation": [
                    "type": "boolean",
                    "description": "Also include captures without a screenshot (plain dictation). Default false.",
                ],
            ],
        ],
    ]

    static func run() -> Never {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let reply = handle(msg) { send(reply) }
        }
        exit(0)
    }

    private static func send(_ obj: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private static func ok(_ id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func fail(_ id: Any, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    static func handle(_ msg: [String: Any]) -> [String: Any]? {
        guard let id = msg["id"], !(id is NSNull) else { return nil }  // notifications get no reply
        let method = msg["method"] as? String ?? ""
        let params = msg["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            return ok(id, [
                "protocolVersion": params["protocolVersion"] as? String ?? fallbackProtocol,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "point", "version": version],
                "instructions": instructions,
            ])
        case "ping":
            return ok(id, [:])
        case "tools/list":
            return ok(id, ["tools": [tool]])
        case "tools/call":
            guard (params["name"] as? String) == "last_capture" else {
                return fail(id, -32602, "Unknown tool: \(params["name"] as? String ?? "")")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let count = max(1, min(5, (args["count"] as? NSNumber)?.intValue ?? 1))
            let dictation = (args["include_dictation"] as? NSNumber)?.boolValue ?? false
            return ok(id, ["content": lastCaptures(count: count, includeDictation: dictation)])
        default:
            return fail(id, -32601, "Method not found: \(method)")
        }
    }

    // ─── Reading captures ─────────────────────────────────────────────────────

    static func lastCaptures(count: Int, includeDictation: Bool) -> [[String: Any]] {
        let dir = CAPTURES_DIR
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("point_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }   // ids are timestamps

        var content: [[String: Any]] = []
        var found = 0
        for f in files.prefix(200) where found < count {
            guard let data = try? Data(contentsOf: f),
                  let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            var shot: URL?
            if let p = meta["screenshot"] as? String, !p.isEmpty {
                let local = dir.appendingPathComponent((p as NSString).lastPathComponent)
                if FileManager.default.fileExists(atPath: local.path) { shot = local }
            }
            if shot == nil && !includeDictation { continue }
            found += 1
            content.append(["type": "text", "text": describe(meta, screenshot: shot, index: found, of: count)])
            if let shot, let jpeg = jpeg(shot, maxSide: 1568) {
                content.append(["type": "image", "data": jpeg.base64EncodedString(), "mimeType": "image/jpeg"])
            }
        }
        if found == 0 {
            content.append(["type": "text", "text": includeDictation
                ? "The user has no Point captures yet. To make one, they hold their trigger key (Left Control by default) and talk."
                : "The user has no Point captures with a screenshot yet. To make one, they hold their trigger key (Left Control by default), talk, and draw a loop around something on screen."])
        }
        return content
    }

    private static func describe(_ meta: [String: Any], screenshot: URL?, index: Int, of total: Int) -> String {
        let said = (meta["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = [total > 1 ? "Point capture \(index) (newest first)" : "Point capture"]
        lines.append(said.isEmpty ? "Said: (nothing, just the mark)" : "Said: \"\(said)\"")
        if let app = meta["app"] as? String, !app.isEmpty { lines.append("App in front: \(app)") }
        if let iso = meta["created_at"] as? String, let date = ISO8601DateFormatter().date(from: iso) {
            let abs = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
            let rel = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
            lines.append("When: \(abs) (\(rel))")
        }
        if let screenshot {
            lines.append("Screenshot file: \(screenshot.path)")
            lines.append("The red loop or rectangle on the screenshot marks what the user means by \"this\". The words may contain dictation mistakes, especially in product and code names.")
        } else {
            lines.append("No screenshot: this was plain dictation.")
        }
        return lines.joined(separator: "\n")
    }

    /// A downscaled JPEG of the screenshot, small enough to pass to a model.
    private static func jpeg(_ url: URL, maxSide: Int) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
