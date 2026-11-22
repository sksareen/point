// Which modifier key drives Point (hold = talk/circle, double-tap = sticky pad). Default: Left ⌃.
// Chosen from the menu bar; persisted in UserDefaults.

import Cocoa

enum TriggerKey: String, CaseIterable {
    case rightOption, leftControl, rightCommand, fn

    static let changed = Notification.Name("PointTriggerKeyChanged")
    private static let defaultsKey = "triggerKey"

    static var current: TriggerKey {
        get {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(TriggerKey.init(rawValue:)) ?? .leftControl
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /// The default was Right ⌥ through 0.1.2 and is Left ⌃ after. Someone who installed an
    /// earlier build and never picked a key keeps Right ⌥, so an update doesn't move their key.
    /// Call once at launch, before anything creates Point's data folder.
    static func keepKeyForExistingInstall() {
        guard UserDefaults.standard.string(forKey: defaultsKey) == nil,
              FileManager.default.fileExists(atPath: POINT_DIR.path) else { return }
        UserDefaults.standard.set(TriggerKey.rightOption.rawValue, forKey: defaultsKey)
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

    /// Spoken name, e.g. "Left Control".
    var name: String {
        switch self {
        case .rightOption: return "Right Option"
        case .leftControl: return "Left Control"
        case .rightCommand: return "Right Command"
        case .fn: return "Fn"
        }
    }

    /// What's printed on the key.
    var capLabel: String {
        switch self {
        case .rightOption: return "option"
        case .leftControl: return "control"
        case .rightCommand: return "command"
        case .fn: return "fn"
        }
    }

    /// Menu label, with any caveat the user should know before picking it.
    var menuTitle: String {
        switch self {
        case .rightOption: return "Right ⌥ Option (never clashes with shortcuts)"
        case .leftControl: return "Left ⌃ Control (default)"
        case .rightCommand: return "Right ⌘ Command"
        case .fn: return "Fn / 🌐 (set 🌐 key to “Do Nothing” in Keyboard settings)"
        }
    }
}

/// How you mark the screen while holding the trigger: a freehand loop, or a dragged rectangle.
enum MarkStyle: String, CaseIterable {
    case loop, rectangle

    private static let defaultsKey = "markStyle"

    static var current: MarkStyle {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(MarkStyle.init(rawValue:)) ?? .loop }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var title: String {
        switch self {
        case .loop: return "Circle (draw freehand)"
        case .rectangle: return "Rectangle (drag a box)"
        }
    }

    /// Hint shown in the overlay before anything is marked.
    var hint: String {
        switch self {
        case .loop: return "draw a loop to add a screenshot"
        case .rectangle: return "drag a box to add a screenshot"
        }
    }
}
