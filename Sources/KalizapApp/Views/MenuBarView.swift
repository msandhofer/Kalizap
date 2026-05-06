import SwiftUI
import Kalizap

struct MenuBarView: View {
    @Bindable var settings: SettingsManager
    var pipeline: DictationPipeline?
    var historyVM: HistoryViewModel
    var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 8) {
            Text("Kalizap")
                .font(.headline)
                .padding(.top, 8)

            UpdateBannerView(
                state: appState.updateState,
                dismissedVersion: settings.system.dismissedUpdateVersion,
                onDismiss: { version in appState.dismissUpdateVersion(version) },
                strings: UpdateBannerLocalization.strings(
                    for: .from(localeIdentifier: Locale.current.language.languageCode?.identifier)
                )
            )

            pipelineStatusView

            apiKeyStatusView

            recentTranscriptionsView

            Divider()

            HStack {
                Button {
                    activateAndOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .keyboardShortcut(",")
                .help("Einstellungen")

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .keyboardShortcut("q")
                .help("Beenden")
            }
            .buttonStyle(.plain)
            .font(.title3)
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
                ModelLoadingView(progress: progress)

            case .recording:
                RecordingStatusView(bands: pipeline.spectrumBands)

            case .processing(let stage):
                ProcessingStatusView(stage: stage, onCancel: pipeline.cancelDictation)

            case .pendingInClipboard:
                Label("Text in Zwischenablage", systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.orange)

            case .error(let error):
                PipelineErrorView(error: error, onRetry: {
                    pipeline.dismissError()
                    Task { await pipeline.loadModelAndActivate() }
                }, onSettings: activateAndOpenSettings)

            case .idle:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var apiKeyStatusView: some View {
        HStack(spacing: 4) {
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

            if settings.apiKeyStatus != .validating {
                Button {
                    Task { await settings.validateAPIKey() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("API-Key erneut prüfen")
            }
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
        WindowActivation.activateTemporarily { openWindow(id: "settings") }
    }
}

// MARK: - Pipeline Status Sub-Views

private struct ModelLoadingView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 4) {
            ProgressView(value: progress)
                .padding(.horizontal, 8)
            Text("Modell wird geladen… \(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecordingStatusView: View {
    let bands: [Float]

    var body: some View {
        SpectrumView(bands: bands, barCount: 12, height: 20, barWidth: 2, spacing: 2)
            .padding(.horizontal, 8)
        Text("Aufnahme läuft…")
            .font(.caption)
            .foregroundStyle(.red)
    }
}

private struct ProcessingStatusView: View {
    let stage: PipelineState.ProcessingStage
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)
            Text(stage.localizedLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if stage == .transcribing {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PipelineErrorView: View {
    let error: PipelineError
    let onRetry: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .help(error.message)
                .textSelection(.enabled)
            if error.isRecoverable {
                HStack(spacing: 8) {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Erneut versuchen")

                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                    }
                    .help("Einstellungen")
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
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
