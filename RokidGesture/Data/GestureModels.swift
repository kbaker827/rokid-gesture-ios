import Foundation
import SwiftUI
import Vision

// MARK: - Static gestures (from a single frame)

enum GestureType: String, CaseIterable, Identifiable, Equatable {
    case fist       = "Fist"        // ✊ all fingers curled
    case openPalm   = "Open Palm"   // 🖐 all 5 extended
    case pointOne   = "Point"       // ☝️ index only
    case peaceSign  = "Peace Sign"  // ✌️ index + middle
    case thumbsUp   = "Thumbs Up"   // 👍 thumb up, others curled
    case thumbsDown = "Thumbs Down" // 👎 thumb down, others curled
    case none       = "None"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .fist:       return "✊"
        case .openPalm:   return "🖐"
        case .pointOne:   return "☝️"
        case .peaceSign:  return "✌️"
        case .thumbsUp:   return "👍"
        case .thumbsDown: return "👎"
        case .none:       return "—"
        }
    }

    // Dynamic swipe gestures are separate
    static var staticCases: [GestureType] {
        [.fist, .openPalm, .pointOne, .peaceSign, .thumbsUp, .thumbsDown]
    }
}

// Dynamic gestures (from wrist movement history)
enum SwipeGesture: String, Equatable {
    case left  = "Swipe Left"
    case right = "Swipe Right"
    case up    = "Swipe Up"
    case down  = "Swipe Down"

    var emoji: String {
        switch self {
        case .left:  return "←"
        case .right: return "→"
        case .up:    return "↑"
        case .down:  return "↓"
        }
    }
}

// MARK: - Navigation actions

enum NavAction: String, CaseIterable, Identifiable {
    case next     = "Next Item"
    case previous = "Previous Item"
    case select   = "Select / Confirm"
    case back     = "Back / Cancel"
    case scrollUp = "Scroll Up"
    case scrollDown = "Scroll Down"
    case none     = "No Action"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .next:       return "arrow.right"
        case .previous:   return "arrow.left"
        case .select:     return "checkmark.circle.fill"
        case .back:       return "arrow.uturn.left"
        case .scrollUp:   return "arrow.up"
        case .scrollDown: return "arrow.down"
        case .none:       return "minus"
        }
    }
}

// MARK: - Gesture → action mapping

struct GestureMapping: Codable {
    var fist:       NavAction = .back
    var openPalm:   NavAction = .select
    var pointOne:   NavAction = .next
    var peaceSign:  NavAction = .previous
    var thumbsUp:   NavAction = .scrollUp
    var thumbsDown: NavAction = .scrollDown
    var swipeLeft:  NavAction = .previous
    var swipeRight: NavAction = .next
    var swipeUp:    NavAction = .scrollUp
    var swipeDown:  NavAction = .scrollDown

    func action(for gesture: GestureType) -> NavAction {
        switch gesture {
        case .fist:       return fist
        case .openPalm:   return openPalm
        case .pointOne:   return pointOne
        case .peaceSign:  return peaceSign
        case .thumbsUp:   return thumbsUp
        case .thumbsDown: return thumbsDown
        case .none:       return .none
        }
    }

    func action(for swipe: SwipeGesture) -> NavAction {
        switch swipe {
        case .left:  return swipeLeft
        case .right: return swipeRight
        case .up:    return swipeUp
        case .down:  return swipeDown
        }
    }
}

// MARK: - Menu items

struct MenuItem: Identifiable, Codable, Equatable {
    var id:       String = UUID().uuidString
    var title:    String
    var icon:     String   // SF Symbol name
    var subtitle: String   // shown on glasses beneath the title

    init(title: String, icon: String = "circle.fill", subtitle: String = "") {
        self.title    = title
        self.icon     = icon
        self.subtitle = subtitle
    }
}

// MARK: - App menu state

class AppMenu: ObservableObject {
    @Published var items:         [MenuItem]
    @Published var selectedIndex: Int = 0

    init(items: [MenuItem] = MenuItem.defaultItems) {
        self.items = items
    }

    var selectedItem: MenuItem? {
        guard !items.isEmpty, selectedIndex < items.count else { return nil }
        return items[selectedIndex]
    }

    func moveNext() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
    }

    func movePrev() {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + items.count) % items.count
    }

    func moveFirst() { selectedIndex = 0 }
    func moveLast()  { selectedIndex = max(0, items.count - 1) }

    // Serialised menu text for glasses
    func glassesText(format: GlassesFormat) -> String {
        guard !items.isEmpty else { return "No menu items" }
        switch format {
        case .full:
            return items.enumerated().map { i, item in
                let prefix = i == selectedIndex ? "▶" : " "
                return "\(prefix) \(item.title)"
            }.joined(separator: "\n")
        case .compact:
            let item = items[selectedIndex]
            return "[\(selectedIndex + 1)/\(items.count)] \(item.title)"
        case .minimal:
            return items[selectedIndex].title
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "gesture_menu_items")
        }
        UserDefaults.standard.set(selectedIndex, forKey: "gesture_menu_selected")
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: "gesture_menu_items"),
           let saved = try? JSONDecoder().decode([MenuItem].self, from: data) {
            items = saved
        }
        selectedIndex = UserDefaults.standard.integer(forKey: "gesture_menu_selected")
        if selectedIndex >= items.count { selectedIndex = 0 }
    }
}

extension MenuItem {
    static let defaultItems: [MenuItem] = [
        .init(title: "Home",          icon: "house.fill",              subtitle: "Go to home screen"),
        .init(title: "Notifications", icon: "bell.fill",               subtitle: "View alerts"),
        .init(title: "Apps",          icon: "square.grid.2x2.fill",    subtitle: "App launcher"),
        .init(title: "Settings",      icon: "gear",                    subtitle: "System settings"),
        .init(title: "Media",         icon: "play.circle.fill",        subtitle: "Music & video"),
        .init(title: "Navigation",    icon: "map.fill",                subtitle: "Maps & directions"),
        .init(title: "Camera",        icon: "camera.fill",             subtitle: "Take photos"),
        .init(title: "Calls",         icon: "phone.fill",              subtitle: "Phone & contacts"),
    ]
}

// MARK: - Glasses format

enum GlassesFormat: String, CaseIterable, Identifiable {
    case full    = "full"
    case compact = "compact"
    case minimal = "minimal"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .full:    return "Full List"
        case .compact: return "Compact"
        case .minimal: return "Minimal"
        }
    }
    var description: String {
        switch self {
        case .full:    return "All items with ▶ cursor"
        case .compact: return "[2/8] Apps — position + name"
        case .minimal: return "Just the selected item name"
        }
    }
}

// MARK: - Hand points for overlay drawing

typealias JointName = VNHumanHandPoseObservation.JointName

struct HandPoints {
    let joints: [JointName: CGPoint]   // Vision normalized (0,0=bottom-left, y-up)

    var wrist: CGPoint? { joints[.wrist] }

    subscript(_ name: JointName) -> CGPoint? { joints[name] }

    var isEmpty: Bool { joints.isEmpty }

    var allPoints: [(JointName, CGPoint)] { Array(joints) }
}
