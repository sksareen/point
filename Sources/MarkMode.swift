// How you mark the screen while holding the trigger key:
//   draw   → freehand loop around what you mean (the default)
//   select → drag a red box over it, like a screenshot selection
// Chosen in Settings; persisted in UserDefaults.

import Cocoa

enum MarkMode: String, CaseIterable {
    case draw, select

    static let changed = Notification.Name("PointMarkModeChanged")
    private static let defaultsKey = "markMode"

    static var current: MarkMode {
        get {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(MarkMode.init(rawValue:)) ?? .draw
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /// Settings label.
    var title: String {
        switch self {
        case .draw: return "Draw: circle it freehand"
        case .select: return "Select: drag a red box"
        }
    }

    /// Short verb for menu and hint text, e.g. "draw → + screenshot".
    var verb: String {
        switch self {
        case .draw: return "draw"
        case .select: return "drag a box"
        }
    }

    /// Hint shown in the recording pill before anything is marked.
    var hint: String {
        switch self {
        case .draw: return "draw a loop to add a screenshot"
        case .select: return "drag a box to add a screenshot"
        }
    }
}

/// The box a select-mode stroke spans: its first point to its last.
func boxRect(_ stroke: [NSPoint]) -> NSRect {
    guard let a = stroke.first, let b = stroke.last else { return .zero }
    return NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
}
