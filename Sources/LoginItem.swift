// Menu plumbing: version label, launch at login, quick folder access.

import Cocoa
import ServiceManagement

let APP_VERSION: String = {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "?"
    let build = info["CFBundleVersion"] as? String ?? "?"
    let channel = info["PointChannel"] as? String ?? "dev"
    return "\(version) (\(channel) · \(build))"
}()

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns the new state. Registration only sticks for an app at a stable path (/Applications).
    @discardableResult
    static func toggle() -> Bool {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Point: login item toggle failed: \(error)")
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        return isEnabled
    }
}

extension PointAppDelegate: NSMenuDelegate {
    /// Adds the dev-mode section to the status menu (call after the base items are added).
    func addDevModeItems(to menu: NSMenu) {
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.tag = 9001
        menu.addItem(login)

        let version = NSMenuItem(title: "Point \(APP_VERSION)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        menu.delegate = self
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTag: 9001)?.state = LoginItem.isEnabled ? .on : .off
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        sender.state = LoginItem.toggle() ? .on : .off
    }
}
