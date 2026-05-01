import SwiftUI

struct ContentView: View {
    @StateObject private var vm = GestureViewModel()

    var body: some View {
        TabView {
            CameraView()
                .tabItem { Label("Camera", systemImage: "hand.raised.fill") }

            MenuBuilderView()
                .tabItem { Label("Menu", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .environmentObject(vm)
        .tint(.yellow)
        .preferredColorScheme(.dark)
    }
}
