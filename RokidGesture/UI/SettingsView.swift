import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vm: GestureViewModel

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Connection
                Section("Connection") {
                    HStack {
                        Circle().fill(vm.glassesServer.isRunning ? .cyan : .red)
                            .frame(width: 8, height: 8)
                        Text(vm.isGlassesWatching
                             ? "\(vm.glassesServer.clientCount) glasses on :8104"
                             : "Waiting for glasses on :8104")
                            .foregroundStyle(vm.isGlassesWatching ? .cyan : .secondary)
                    }
                    Button("Push menu to glasses now") {
                        vm.pushMenuToGlasses()
                    }
                    .disabled(!vm.isGlassesWatching)
                }

                // MARK: Detection
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Gesture cooldown")
                            Spacer()
                            Text(String(format: "%.1f s", vm.gestureCooldown))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get:  { vm.gestureCooldown },
                            set:  { vm.setCooldown($0) }
                        ), in: 0.3...3.0, step: 0.1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Swipe sensitivity")
                            Spacer()
                            Text(String(format: "%.2f", vm.swipeThreshold))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get:  { vm.swipeThreshold },
                            set:  { vm.setSwipeThreshold($0) }
                        ), in: 0.05...0.35, step: 0.01)
                        Text("Lower = easier to trigger swipes. Default: 0.18")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Detection")
                }

                // MARK: Gesture mappings
                Section {
                    gestureRow(label: "✊ Fist",        binding: gestureBinding(\.fist))
                    gestureRow(label: "🖐 Open Palm",   binding: gestureBinding(\.openPalm))
                    gestureRow(label: "☝️ Point",        binding: gestureBinding(\.pointOne))
                    gestureRow(label: "✌️ Peace Sign",   binding: gestureBinding(\.peaceSign))
                    gestureRow(label: "👍 Thumbs Up",   binding: gestureBinding(\.thumbsUp))
                    gestureRow(label: "👎 Thumbs Down", binding: gestureBinding(\.thumbsDown))
                    Divider()
                    gestureRow(label: "← Swipe Left",  binding: gestureBinding(\.swipeLeft))
                    gestureRow(label: "→ Swipe Right",  binding: gestureBinding(\.swipeRight))
                    gestureRow(label: "↑ Swipe Up",     binding: gestureBinding(\.swipeUp))
                    gestureRow(label: "↓ Swipe Down",   binding: gestureBinding(\.swipeDown))
                } header: {
                    Text("Gesture → Action Mapping")
                } footer: {
                    Text("Change what each gesture does in the menu.")
                }

                // MARK: Glasses display
                Section {
                    Picker("Display format", selection: Binding(
                        get:  { vm.glassesFormat },
                        set:  { vm.setGlassesFormat($0) }
                    )) {
                        ForEach(GlassesFormat.allCases) { fmt in
                            VStack(alignment: .leading) {
                                Text(fmt.displayName)
                                Text(fmt.description).font(.caption).foregroundStyle(.secondary)
                            }.tag(fmt)
                        }
                    }
                } header: {
                    Text("Glasses Display")
                }

                // MARK: Gesture guide
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        tip("Hold hand upright", detail: "Palm facing the camera, fingers pointing up")
                        tip("Keep hand still between gestures", detail: "Cooldown prevents accidental repeats")
                        tip("Swipe = move wrist", detail: "Quick directional wrist movement, no need to sweep the whole arm")
                        tip("Works with front or back camera", detail: "Flip using the camera icon in the Camera tab")
                    }
                } header: {
                    Text("Tips for Best Results")
                }

                // MARK: About
                Section("About") {
                    LabeledContent("App",      value: "Rokid Gesture HUD")
                    LabeledContent("Port",     value: ":8104")
                    LabeledContent("Framework", value: "Vision VNDetectHumanHandPoseRequest")
                    LabeledContent("Version",  value: "1.0")
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Helpers

    private func gestureRow(label: String, binding: Binding<NavAction>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Picker("", selection: binding) {
                ForEach(NavAction.allCases) { action in
                    Label(action.rawValue, systemImage: action.icon).tag(action)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func gestureBinding(_ kp: WritableKeyPath<GestureMapping, NavAction>) -> Binding<NavAction> {
        Binding(
            get:  { vm.gestureMapping[keyPath: kp] },
            set:  { vm.gestureMapping[keyPath: kp] = $0; vm.saveMapping() }
        )
    }

    private func tip(_ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
