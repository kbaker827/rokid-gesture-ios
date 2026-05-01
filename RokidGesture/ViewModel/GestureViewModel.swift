import Foundation
import Combine
import CoreGraphics

@MainActor
final class GestureViewModel: ObservableObject {

    // MARK: - Published state
    @Published var currentGesture:    GestureType = .none
    @Published var lastFiredGesture:  String      = ""     // display string for last fired event
    @Published var isDetecting:       Bool        = false
    @Published var gestureMapping:    GestureMapping = GestureMapping()
    @Published var glassesFormat:     GlassesFormat  = .compact
    @Published var gestureCooldown:   Double         = 1.0   // seconds between fires
    @Published var swipeThreshold:    Double         = 0.18  // normalized wrist displacement

    // MARK: - Sub-objects
    let detector       = HandPoseDetector()
    let glassesServer  = GlassesServer()
    let menu           = AppMenu()
    private let classifier = GestureClassifier()

    // MARK: - Computed
    var isGlassesWatching: Bool { glassesServer.clientCount > 0 }

    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    private var lastFiredTime: Date = .distantPast
    private var wristHistory:  [WristSample] = []

    // MARK: - Init

    init() {
        loadSettings()
        menu.load()
        glassesServer.start()

        // Wire hand pose updates
        detector.onHandPoints = { [weak self] pts in
            self?.processHandPoints(pts)
        }

        // Wire glasses commands
        glassesServer.onGlassesCommand = { [weak self] text in
            self?.handleGlassesCommand(text)
        }
    }

    // MARK: - Detection control

    func startDetection() {
        Task {
            guard await detector.requestPermission() else {
                lastFiredGesture = "⚠️ Camera permission denied"
                return
            }
            detector.setup(front: true)
            detector.start()
            isDetecting = true
            glassesServer.broadcastStatus("Detection started — hold up your hand")
        }
    }

    func stopDetection() {
        detector.stop()
        isDetecting = false
        currentGesture = .none
        glassesServer.broadcastStatus("Detection paused")
    }

    // MARK: - Core processing

    private func processHandPoints(_ pts: HandPoints?) {
        guard let pts else {
            currentGesture = .none
            wristHistory.removeAll()
            return
        }

        // Track wrist for swipe detection
        if let wrist = pts.wrist {
            let now = Date()
            wristHistory.append(WristSample(pos: wrist, time: now))
            // Keep only last 0.5 seconds
            wristHistory = wristHistory.filter { now.timeIntervalSince($0.time) < 0.5 }
        }

        // Classify static gesture
        let gesture = classifier.classify(pts)
        currentGesture = gesture

        // Check for swipe (dynamic)
        if let swipe = detectSwipe() {
            fireSwipe(swipe)
            wristHistory.removeAll()   // reset after swipe fires
            return
        }

        // Fire static gesture if stable
        if gesture != .none { fireGesture(gesture) }
    }

    // MARK: - Swipe detection

    private struct WristSample { let pos: CGPoint; let time: Date }

    private func detectSwipe() -> SwipeGesture? {
        guard wristHistory.count >= 4 else { return nil }
        let first = wristHistory.first!.pos
        let last  = wristHistory.last!.pos
        let dx = last.x - first.x
        let dy = last.y - first.y   // Vision y-up: positive = hand moves up
        let magnitude = max(abs(dx), abs(dy))
        guard magnitude >= swipeThreshold else { return nil }

        if abs(dx) >= abs(dy) {
            return dx > 0 ? .right : .left
        } else {
            return dy > 0 ? .up : .down   // Vision y-up
        }
    }

    // MARK: - Firing

    private func fireGesture(_ gesture: GestureType) {
        guard canFire() else { return }
        let action = gestureMapping.action(for: gesture)
        guard action != .none else { return }
        lastFiredTime = Date()
        applyAction(action)
        let display = "\(gesture.emoji) \(gesture.rawValue) → \(action.rawValue)"
        lastFiredGesture = display
        glassesServer.broadcastGesture(gesture.emoji,
                                       gestureName: gesture.rawValue,
                                       actionName: action.rawValue)
    }

    private func fireSwipe(_ swipe: SwipeGesture) {
        guard canFire() else { return }
        let action = gestureMapping.action(for: swipe)
        guard action != .none else { return }
        lastFiredTime = Date()
        applyAction(action)
        let display = "\(swipe.emoji) \(swipe.rawValue) → \(action.rawValue)"
        lastFiredGesture = display
        glassesServer.broadcastGesture(swipe.emoji,
                                       gestureName: swipe.rawValue,
                                       actionName: action.rawValue)
    }

    private func canFire() -> Bool {
        Date().timeIntervalSince(lastFiredTime) >= gestureCooldown
    }

    // MARK: - Menu navigation

    private func applyAction(_ action: NavAction) {
        switch action {
        case .next:       menu.moveNext()
        case .previous:   menu.movePrev()
        case .scrollUp:   menu.moveFirst()
        case .scrollDown: menu.moveLast()
        case .select:
            if let item = menu.selectedItem {
                glassesServer.broadcastSelect(item.title)
            }
        case .back:
            glassesServer.broadcastStatus("← Back")
        case .none: break
        }
        pushMenuToGlasses()
        menu.save()
    }

    func pushMenuToGlasses() {
        guard glassesServer.clientCount > 0 else { return }
        glassesServer.broadcastMenu(menu.glassesText(format: glassesFormat))
    }

    // MARK: - Glasses commands

    private func handleGlassesCommand(_ text: String) {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch lower {
        case "next":     applyAction(.next)
        case "prev", "previous": applyAction(.previous)
        case "select":   applyAction(.select)
        case "back":     applyAction(.back)
        case "up":       applyAction(.scrollUp)
        case "down":     applyAction(.scrollDown)
        case "menu":     pushMenuToGlasses()
        default:         glassesServer.broadcastStatus("Unknown: \(text)")
        }
    }

    // MARK: - Settings persistence

    func setGlassesFormat(_ fmt: GlassesFormat) {
        glassesFormat = fmt
        UserDefaults.standard.set(fmt.rawValue, forKey: "gesture_glasses_format")
    }

    func setCooldown(_ v: Double) {
        gestureCooldown = v
        UserDefaults.standard.set(v, forKey: "gesture_cooldown")
    }

    func setSwipeThreshold(_ v: Double) {
        swipeThreshold = v
        UserDefaults.standard.set(v, forKey: "gesture_swipe_threshold")
    }

    func saveMapping() {
        if let data = try? JSONEncoder().encode(gestureMapping) {
            UserDefaults.standard.set(data, forKey: "gesture_mapping")
        }
    }

    private func loadSettings() {
        let ud = UserDefaults.standard
        if let raw = ud.string(forKey: "gesture_glasses_format"),
           let fmt = GlassesFormat(rawValue: raw) { glassesFormat = fmt }
        let cd = ud.double(forKey: "gesture_cooldown")
        if cd > 0 { gestureCooldown = cd }
        let st = ud.double(forKey: "gesture_swipe_threshold")
        if st > 0 { swipeThreshold = st }
        if let data = ud.data(forKey: "gesture_mapping"),
           let m = try? JSONDecoder().decode(GestureMapping.self, from: data) {
            gestureMapping = m
        }
    }
}
