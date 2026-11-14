// Optional integration with Sauron (a local activity-context daemon).
// If a `sauron` binary is installed, each screenshot is also registered in its
// timeline. If not, this does nothing. Point never depends on it.

import Cocoa

enum SauronHook {
    private static let binary: String? = {
        let candidates = [
            "/usr/local/bin/sauron",
            "/opt/homebrew/bin/sauron",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("go/bin/sauron").path,
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static func register(screenshot path: String, app: NSRunningApplication?) {
        guard let binary else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["capture", "--register", path,
                          "--source-app", app?.localizedName ?? "unknown",
                          "--bundle-id", app?.bundleIdentifier ?? ""]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}
