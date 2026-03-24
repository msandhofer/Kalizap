import SwiftUI
import DerFluisterer

@main
struct DerFluistererApp: App {
    var body: some Scene {
        MenuBarExtra("DerFlüsterer", systemImage: "mic.fill") {
            Text("DerFlüsterer")
                .padding()
            Divider()
            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)
    }
}
