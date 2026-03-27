import SwiftUI
import DerFluisterer

struct MenuBarView: View {
    @Bindable var settings: SettingsManager
    var pipeline: DictationPipeline?
    var updater: SparkleUpdater?
    var historyVM: HistoryViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 8) {
            Text("DerFlüsterer")
                .font(.headline)
                .padding(.top, 8)

            pipelineStatusView

            apiKeyStatusView

            recentTranscriptionsView

            Divider()

            Button("Nach Updates suchen…") {
                updater?.checkForUpdates()
            }
            .disabled(updater?.canCheckForUpdates != true)

            Button("Einstellungen…") {
                activateAndOpenSettings()
            }
            .keyboardShortcut(",")

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
        .task {
            await historyVM.startObserving()
        }
    }

    @ViewBuilder
    private var pipelineStatusView: some View {
        if let pipeline {
            switch pipeline.state {
            case .loadingModel(let progress):
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .padding(.horizontal, 8)
                    Text("Modell wird geladen… \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .recording:
                WaveformView(levels: [pipeline.audioLevel])
                    .padding(.horizontal, 8)
                Text("Aufnahme läuft…")
                    .font(.caption)
                    .foregroundStyle(.red)

            case .processing(let stage):
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text(stage.localizedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if stage == .transcribing {
                        Button { pipeline.cancelDictation() } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

            case .pendingInClipboard:
                Label("Text in Zwischenablage", systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.orange)

            case .error(let error):
                VStack(spacing: 4) {
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .help(error.message)
                        .textSelection(.enabled)
                    if error.isRecoverable {
                        HStack(spacing: 8) {
                            Button("Erneut versuchen") {
                                pipeline.dismissError()
                                Task { await pipeline.loadModelAndActivate() }
                            }
                            .font(.caption)

                            Button("Einstellungen") {
                                activateAndOpenSettings()
                            }
                            .font(.caption)
                        }
                    }
                }

            case .idle:
                EmptyView()
            }
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

    @ViewBuilder
    private var recentTranscriptionsView: some View {
        let recent = Array(historyVM.entries.prefix(3))
        if !recent.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                ForEach(recent, id: \.id) { entry in
                    Button {
                        historyVM.copyToClipboard(entry)
                    } label: {
                        ZStack {
                            Text(entry.correctedText)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .opacity(historyVM.copiedEntryID == entry.id ? 0 : 1)

                            if historyVM.copiedEntryID == entry.id {
                                Text("Kopiert!")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func activateAndOpenSettings() {
        NSApp.setActivationPolicy(.regular)
        openSettings()
        DispatchQueue.main.async {
            NSApp.activate()
            for window in NSApp.windows where window.isVisible {
                window.orderFrontRegardless()
            }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private extension PipelineState.ProcessingStage {
    var localizedLabel: String {
        switch self {
        case .transcribing: "Transkribiere…"
        case .correcting: "Korrigiere…"
        case .inserting: "Füge ein…"
        }
    }
}
