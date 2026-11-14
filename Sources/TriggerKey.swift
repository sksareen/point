// Which modifier key drives Point (hold = talk/circle, double-tap = sticky pad).
// Chosen from the menu bar; persisted in UserDefaults.

import Cocoa

enum TriggerKey: String, CaseIterable {
    case rightOption, leftControl, rightCommand, fn

    static let changed = Notification.Name("PointTriggerKeyChanged")
    private static let defaultsKey = "triggerKey"

    static var current: TriggerKey {
        get {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(TriggerKey.init(rawValue:)) ?? .rightOption
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /// Virtual key code reported in .flagsChanged events for this physical key.
    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .leftControl: return 59
        case .rightCommand: return 54
        case .fn: return 63
        }
    }

    /// Whether this specific physical key is down. Uses device-dependent bits so that,
    /// e.g., Left ⌥ doesn't count as Right ⌥.
    func isDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .rightOption: return flags.rawValue & 0x40 != 0   // NX_DEVICERALTKEYMASK
        case .leftControl: return flags.rawValue & 0x01 != 0   // NX_DEVICELCTLKEYMASK
        case .rightCommand: return flags.rawValue & 0x10 != 0  // NX_DEVICERCMDKEYMASK
        case .fn: return flags.contains(.function)
        }
    }

    /// Short name for labels, e.g. "Right ⌥".
    var symbol: String {
        switch self {
        case .rightOption: return "Right ⌥"
        case .leftControl: return "Left ⌃"
        case .rightCommand: return "Right ⌘"
        case .fn: return "Fn"
        }
    }

    /// Menu label, with any caveat the user should know before picking it.
    var menuTitle: String {
        switch self {
        case .rightOption: return "Right ⌥ Option (recommended)"
        case .leftControl: return "Left ⌃ Control (mic flickers on ⌃ shortcuts)"
        case .rightCommand: return "Right ⌘ Command"
        case .fn: return "Fn / 🌐 (set 🌐 key to “Do Nothing” in Keyboard settings)"
        }
    }
}
