import SwiftUI

@main
struct DecantApp: App {
    @State private var store = Store()

    init() {
        // Running from `swift run` has no bundle; make it a normal foreground app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Decant") {
            ContentView()
                .environment(store)
                .frame(minWidth: 820, minHeight: 520)
                .task { await store.refresh() }
        }
        Settings {
            SetupView().environment(store).frame(width: 520, height: 460)
        }
    }
}
