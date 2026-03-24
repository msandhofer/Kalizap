import SwiftUI
import DerFluisterer

struct MenuBarView: View {
    @Bindable var settings: SettingsManager
    var recordingVM: RecordingViewModel

    var body: some View {
        VStack(spacing: 8) {
            Text("DerFlüsterer")
                .font(.headline)
                .padding(.top, 8)

            if recordingVM.isRecording {
                WaveformView(levels: recordingVM.waveformLevels)
                    .padding(.horizontal, 8)

                Text("Aufnahme läuft…")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            apiKeyStatusView

            Divider()

            Button("Einstellungen…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
        .task {
            await settings.validateAPIKey()
        }
    }

    @ViewBuilder
    private var apiKeyStatusView: some View {
        switch settings.apiKeyStatus {
        case .missing:
            Label("API-Key fehlt", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .validating:
            Label("API-Key wird geprüft…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
        case .valid:
            Label("API-Key gültig", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .invalid(let message):
            Label("API-Key ungültig: \(message)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}
