# Rokid Gesture HUD


> **🔵 Connectivity Update — May 2025**
> The glasses connection has been migrated from **raw TCP sockets** to
> **Bluetooth via the Rokid AI glasses SDK** (`pod 'RokidSDK' ~> 1.10.2`).
> No Wi-Fi port forwarding is needed. See **SDK Setup** below.

Navigate menus on your Rokid AR glasses using hand gestures — iPhone camera detects your hand pose via Apple's Vision framework and sends navigation events to the glasses over TCP.

```
iPhone Camera
    ↓
Vision VNDetectHumanHandPoseRequest (21-joint hand skeleton)
    ↓
GestureClassifier → GestureType → NavAction
    ↓  (also: wrist movement history → SwipeGesture)
GestureViewModel
    ↓
TCP :8104 → Rokid Glasses
  {"type":"menu","text":"▶ Home\n  Notifications\n  Apps"}
  {"type":"gesture","text":"✌️ Peace Sign → Previous Item"}
  {"type":"select","text":"✓ Apps"}
```

---

## Gestures

| Gesture | Default Action | Notes |
|---------|---------------|-------|
| ✊ **Fist** | Back / Cancel | All fingers curled |
| 🖐 **Open Palm** | Select / Confirm | All 5 extended |
| ☝️ **Point** | Next Item | Index finger only |
| ✌️ **Peace Sign** | Previous Item | Index + middle |
| 👍 **Thumbs Up** | Scroll to First | Thumb up, others curled |
| 👎 **Thumbs Down** | Scroll to Last | Thumb down, others curled |
| → **Swipe Right** | Next Item | Wrist moves right |
| ← **Swipe Left** | Previous Item | Wrist moves left |
| ↑ **Swipe Up** | Scroll to First | Wrist moves up |
| ↓ **Swipe Down** | Scroll to Last | Wrist moves down |

Every gesture mapping is fully customisable in **Settings → Gesture → Action Mapping**.

---

## SDK Setup

The glasses now connect over **Bluetooth via the Rokid AI glasses SDK** — no Wi-Fi port or TCP server needed.

The only thing left for each app is filling in the three credential constants (`kAppKey`, `kAppSecret`, `kAccessKey`) from [account.rokid.com/#/setting/prove](https://account.rokid.com/#/setting/prove), then running `pod install`.

1. **Get credentials** at <https://account.rokid.com/#/setting/prove> and paste them into the glasses Swift file:
   ```swift
   private let kAppKey    = "YOUR_APP_KEY"
   private let kAppSecret = "YOUR_APP_SECRET"
   private let kAccessKey = "YOUR_ACCESS_KEY"
   ```

2. **Install CocoaPods dependencies** from the repo root:
   ```bash
   pod install
   open *.xcworkspace   # always open the .xcworkspace, not .xcodeproj
   ```

3. *(Glasses now connect automatically over Bluetooth — no TCP port needed.)*

## Quick Start

### 1. Install the iOS app

Open `RokidGesture.xcworkspace` in Xcode 15+ (after running `pod install`) 15+, select your iPhone, and run.  
Grant camera permission when prompted.

### 2. Camera tab

The front camera activates automatically. Hold your hand up — the 21-joint skeleton is drawn in real time. The detected gesture appears as a large emoji badge at the bottom.

### 3. Build your menu (Menu tab)

- Default 8-item menu is pre-loaded (Home, Notifications, Apps, Settings…)
- Tap any item to jump the selection cursor
- Swipe left to delete, tap pencil to edit
- Drag to reorder (tap Edit first)
- Up to 8 items supported

### 4. Connect glasses

Glasses connect to the iPhone on **TCP :8104**. As gestures fire, the glasses receive:
- Updated menu with `▶` cursor
- Gesture event (e.g. `✌️ Peace Sign → Previous Item`)
- Selection confirmation (`✓ Apps`)

---

## Wire Protocol (iPhone → Glasses)

JSON packets, newline-delimited, on TCP :8104:

```json
{"type":"menu",    "text":"▶ Home\n  Notifications\n  Apps\n  Settings"}
{"type":"gesture", "text":"✌️ Peace Sign → Previous Item"}
{"type":"select",  "text":"✓ Apps"}
{"type":"status",  "text":"Detection started — hold up your hand"}
```

### Glasses → iPhone (commands)

```json
{"type":"cmd","text":"next"}
{"type":"cmd","text":"prev"}
{"type":"cmd","text":"select"}
{"type":"cmd","text":"back"}
{"type":"cmd","text":"menu"}
```

---

## Menu Display Formats

| Format | Example |
|--------|---------|
| **Full List** | `▶ Home` / `  Notifications` / `  Apps` (all items, ▶ cursor) |
| **Compact** | `[1/8] Home` |
| **Minimal** | `Home` |

Switch in **Settings → Glasses Display**.

---

## How the Gesture Classifier Works

The Vision framework's `VNDetectHumanHandPoseRequest` gives 21 joint positions per hand. The classifier runs on every 2nd camera frame (~15 classifications/second at 30fps) and uses pure geometry:

**Static gestures** (single frame):
- **Finger extended** = `dist(tip, wrist) / dist(MCP, wrist) > 1.35`
- **Thumb extended** = `dist(thumbTip, wrist) / dist(thumbCMC, wrist) > 1.15`
- Thumb direction = `thumbTip.y vs thumbMP.y` in Vision space (y-up)

**Dynamic gestures** (wrist movement over 0.5s):
- Keep last 500ms of wrist positions
- If `|displacement| > threshold` (default 0.18 in normalized space), fire swipe
- Direction from dominant axis (horizontal vs vertical)

**Cooldown** (default 1.0s): prevents a single held gesture from firing repeatedly. Adjustable from 0.3s to 3.0s in Settings.

---

## Tips for Best Results

- **Hand position** — palm facing camera, fingers pointing upward
- **Distance** — 30–60 cm from the iPhone works best
- **Lighting** — well-lit environment improves Vision confidence
- **Steady wrist** — hold still between gestures (cooldown handles debouncing)
- **Swipe = wrist flick** — no need to move your whole arm; a quick wrist motion is enough
- **Confidence threshold** — joints below 0.4 confidence are ignored (improves reliability)

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| iPhone | iOS 17+, camera |
| Xcode | 15.0+ |
| Glasses | Rokid AI glasses (paired via Bluetooth — no Wi-Fi needed) |
| Camera permission | Required — hand detection only, no images stored or sent |
| CocoaPods | 1.15+ — run `pod install` after cloning |

---

## Project Structure

```
rokid-gesture-ios/
└── RokidGesture/
    ├── App/
    │   ├── RokidGestureApp.swift      ← @main entry point
    │   └── Info.plist                 ← NSCameraUsageDescription
    ├── Data/
    │   └── GestureModels.swift        ← GestureType, NavAction, GestureMapping, MenuItem, AppMenu
    ├── Vision/
    │   ├── HandPoseDetector.swift     ← AVCaptureSession + VNDetectHumanHandPoseRequest
    │   └── GestureClassifier.swift    ← 21-joint geometry → GestureType + bone paths
    ├── Glasses/
    │   └── GlassesServer.swift        ← NWListener :8104, broadcast + inbound commands
    ├── ViewModel/
    │   └── GestureViewModel.swift     ← wrist history, cooldown, menu navigation, glasses relay
    └── UI/
        ├── ContentView.swift          ← 3-tab root (Camera | Menu | Settings)
        ├── CameraView.swift           ← live preview + 21-joint skeleton overlay + gesture badge
        ├── MenuBuilderView.swift      ← add/edit/reorder menu items, glasses preview
        └── SettingsView.swift         ← gesture→action mapping, cooldown, swipe sensitivity
```

---

## Part of the Rokid iOS Bridge Suite

| App | Source | TCP Port | Data Source |
|-----|--------|----------|-------------|
| [rokid-claude-ios](https://github.com/kbaker827/rokid-claude-ios) | Claude AI | :8095 | Anthropic API |
| [rokid-chatgpt-ios](https://github.com/kbaker827/rokid-chatgpt-ios) | ChatGPT | :8096 | OpenAI API |
| [rokid-lansweeper-ios](https://github.com/kbaker827/rokid-lansweeper-ios) | Lansweeper | :8097 | GraphQL API |
| [rokid-teams-ios](https://github.com/kbaker827/rokid-teams-ios) | MS Teams | :8098 | Graph API |
| [rokid-outlook-ios](https://github.com/kbaker827/rokid-outlook-ios) | Outlook | :8099 | Graph API |
| [rokid-compass-ios](https://github.com/kbaker827/rokid-compass-ios) | Compass | :8100 | CoreLocation |
| [rokid-powershell-ios](https://github.com/kbaker827/rokid-powershell-ios) | PowerShell | :8101/:8102 | TCP Bridge |
| [rokid-govee-ios](https://github.com/kbaker827/rokid-govee-ios) | Govee Lights | :8103 | Govee OpenAPI |
| **rokid-gesture-ios** | **Hand Gestures** | **:8104** | **Vision Framework** |
