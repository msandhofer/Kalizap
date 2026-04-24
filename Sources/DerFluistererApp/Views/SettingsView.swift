import AppKit
import SwiftUI
import DerFluisterer

struct SettingsView: View {
    @Bindable var settings: SettingsManager
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            Form {
                HotkeySettingsSection(settings: settings, appState: appState)
                SystemSettingsSection(settings: settings)
                MicrophoneSettingsSection(settings: settings)
                LanguageSettingsSection(settings: settings)
                FeedbackSettingsSection(settings: settings)
                CorrectionSettingsSection(settings: settings)
                APIKeySettingsSection(settings: settings)
                DebugSettingsSection(settings: settings, appState: appState)
            }
            .formStyle(.grouped)
            .padding()
        }
    }
}

// MARK: - Hotkey

struct HotkeySettingsSection: View {
    @Bindable var settings: SettingsManager
    @Bindable var appState: AppState

    var body: some View {
        Section("Hotkey") {
            Picker("Taste", selection: $settings.hotkey.keyCode) {
                ForEach(HotkeyDisplayNames.selectableKeys, id: \.keyCode) { hotkey in
                    Text(hotkey.name).tag(hotkey.keyCode)
                }
            }
            .onChange(of: settings.hotkey.keyCode) { _, _ in
                appState.pipeline?.updateHotkey(settings.hotkey.configuration)
            }

            Toggle("Halten zum Aufnehmen", isOn: $settings.hotkey.requiresHold)
                .onChange(of: settings.hotkey.requiresHold) { _, _ in
                    appState.pipeline?.updateHotkey(settings.hotkey.configuration)
                }
        }
    }
}

// MARK: - System

struct SystemSettingsSection: View {
    @Bindable var settings: SettingsManager
    @State private var autoStartError: String?

    var body: some View {
        Section("System") {
            Toggle("Bei Login starten", isOn: Binding(
                get: { settings.system.autoStart },
                set: { newValue in
                    do {
                        try settings.setAutoStart(newValue)
                        autoStartError = nil
                    } catch {
                        autoStartError = error.localizedDescription
                    }
                }
            ))

            if let autoStartError {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatischer Start fehlgeschlagen: \(autoStartError)")
                        Text("Die App muss dafür im Ordner /Programme/ liegen und signiert sein.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Mikrofon

struct MicrophoneSettingsSection: View {
    @Bindable var settings: SettingsManager
    @State private var devices: [AudioDevice] = []

    var body: some View {
        Section("Mikrofon") {
            Picker("Eingabegerät", selection: Binding(
                get: { settings.audio.microphoneID ?? "" },
                set: { settings.audio.microphoneID = $0.isEmpty ? nil : $0 }
            )) {
                Text("System-Standard").tag("")
                ForEach(devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .onAppear {
                devices = CoreAudioDeviceProvider().listDevices()
            }
        }
    }
}

// MARK: - Sprache

struct LanguageSettingsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section("Sprache") {
            Picker("Sprache", selection: $settings.audio.language) {
                Text("Deutsch").tag(SupportedLanguage.de)
                Text("English").tag(SupportedLanguage.en)
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Feedback

struct FeedbackSettingsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section("Feedback") {
            Toggle("Sounds aktiviert", isOn: $settings.audio.soundsEnabled)
        }
    }
}

// MARK: - Correction (Context, Tasks, Intensity, Prompt-Preview)

struct CorrectionSettingsSection: View {
    @Bindable var settings: SettingsManager

    private var isLLMEnabled: Bool { settings.correction.isLLMEnabled }

    var body: some View {
        Section("Kontext-Modus") {
            Picker("Modus", selection: $settings.correction.contextMode) {
                Text("Formell").tag(ContextMode.formal)
                Text("Informell").tag(ContextMode.informal)
                Text("Neutral").tag(ContextMode.neutral)
                Text("Auto").tag(ContextMode.auto)
            }
            .pickerStyle(.segmented)
            .disabled(!isLLMEnabled)

            if settings.correction.contextMode == .auto {
                Text("Der Stil wird je nach Ziel-App aus der Zuordnungstabelle unten bestimmt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if SettingsVisibility.showAppMapping(
            contextMode: settings.correction.contextMode,
            isLLMEnabled: isLLMEnabled
        ) {
            AppMappingSection(settings: settings)
        }

        Section("Aufgaben") {
            Toggle("Grammatik und Rechtschreibung korrigieren", isOn: $settings.correction.taskGrammar)
            Toggle("Füllwörter entfernen", isOn: $settings.correction.taskFillerRemoval)
            Toggle("Gesprochene Sprache in Schriftsprache umwandeln", isOn: $settings.correction.taskWrittenLanguage)
            Toggle("Zeichensetzung ergänzen", isOn: $settings.correction.taskPunctuation)
            Toggle("Keine Halluzination (keine erfundenen Inhalte)", isOn: $settings.correction.taskPreventHallucination)

            if !isLLMEnabled {
                Label("LLM-Korrektur deaktiviert — Diktat wird nur transkribiert.",
                      systemImage: "info.circle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }

        Section("Korrektur-Intensität") {
            Toggle("Umformulieren erlaubt", isOn: $settings.correction.allowRephrasing)
            Toggle("Kürzen erlaubt", isOn: $settings.correction.allowShortening)
            Toggle("Satzstruktur umstellen erlaubt", isOn: $settings.correction.allowRestructuring)
        }
        .disabled(!isLLMEnabled)

        Section("System-Prompt (Vorschau)") {
            Text(promptPreviewText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    private var promptPreviewText: String {
        CorrectionPrompts.buildSystemPrompt(
            tasks: settings.correction.tasks,
            contextMode: settings.correction.contextMode,
            intensity: CorrectionIntensity(
                allowRephrasing: settings.correction.allowRephrasing,
                allowShortening: settings.correction.allowShortening,
                allowRestructuring: settings.correction.allowRestructuring
            )
        )
    }
}

// MARK: - API Key

struct APIKeySettingsSection: View {
    @Bindable var settings: SettingsManager
    @State private var apiKeyInput = ""
    @State private var showKey = false

    var body: some View {
        Section("Anthropic API-Key") {
            HStack {
                if showKey {
                    TextField("API-Key", text: $apiKeyInput)
                } else {
                    SecureField("API-Key", text: $apiKeyInput)
                }
                Button(showKey ? "Verbergen" : "Anzeigen") {
                    showKey.toggle()
                }
            }

            HStack {
                Button("Speichern") {
                    try? settings.setAPIKey(apiKeyInput)
                    Task { await settings.validateAPIKey() }
                }
                .disabled(apiKeyInput.isEmpty)

                Button("Löschen") {
                    try? settings.deleteAPIKey()
                    apiKeyInput = ""
                }

                Spacer()

                Button("Validieren") {
                    Task { await settings.validateAPIKey() }
                }
            }

            apiKeyStatusLabel
        }
        .onAppear {
            apiKeyInput = settings.apiKey.cachedKey ?? ""
        }
    }

    @ViewBuilder
    private var apiKeyStatusLabel: some View {
        switch settings.apiKeyStatus {
        case .missing:
            Label("Kein API-Key gespeichert", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .validating:
            Label("Wird geprüft…", systemImage: "arrow.triangle.2.circlepath")
        case .valid:
            Label("Gültig", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid(let message):
            Label("Ungültig: \(message)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Debug

struct DebugSettingsSection: View {
    @Bindable var settings: SettingsManager
    @Bindable var appState: AppState

    private var pipelineIsBusy: Bool {
        guard let pipeline = appState.pipeline else { return true }
        if case .loadingModel = pipeline.state { return true }
        return false
    }

    var body: some View {
        Section("Debug-Modus") {
            Toggle("Debug-Modus aktiv", isOn: $settings.system.debugMode)

            if SettingsVisibility.showDebugSections(debugMode: settings.system.debugMode) {
                HStack {
                    Toggle("Rauschunterdrückung (DeepFilterNet3)",
                           isOn: $settings.audio.noiseSuppressionEnabled)
                        .disabled(pipelineIsBusy)
                    if pipelineIsBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Stepper(
                    "History-Limit: \(settings.system.historyLimit)",
                    value: $settings.system.historyLimit,
                    in: 10...1000,
                    step: 10
                )

                Stepper(
                    "LLM-Timeout: \(settings.correction.llmTimeoutMs)ms",
                    value: $settings.correction.llmTimeoutMs,
                    in: 200...5000,
                    step: 100
                )

                Toggle("Hinweis bei fehlender Korrektur anzeigen",
                       isOn: $settings.correction.showAPIKeyNotification)
            }
        }
    }
}

// MARK: - App Mapping

struct AppMappingSection: View {
    @Bindable var settings: SettingsManager
    @State private var selectedBundleID = ""
    @State private var newMode: ContextMode = .formal
    @State private var runningApps: [(bundleID: String, name: String)] = []

    private var sortedMappings: [(key: String, value: ContextMode)] {
        settings.correction.appMapping.sorted { $0.key < $1.key }
    }

    var body: some View {
        Section("App-Zuordnung (Auto-Modus)") {
            ForEach(sortedMappings, id: \.key) { bundleID, mode in
                HStack {
                    if let icon = NSWorkspaceAppDetector.appIcon(for: bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    Text(NSWorkspaceAppDetector.appName(for: bundleID))
                        .lineLimit(1)
                    Spacer()
                    ContextModePicker(label: "", selection: Binding(
                        get: { mode },
                        set: { settings.correction.appMapping[bundleID] = $0 }
                    ))
                    .frame(width: 130)
                    Button(role: .destructive) {
                        settings.correction.appMapping.removeValue(forKey: bundleID)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                Picker("App", selection: $selectedBundleID) {
                    Text("App wählen…").tag("")
                    ForEach(runningApps, id: \.bundleID) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
                .frame(minWidth: 200)

                ContextModePicker(label: "", selection: $newMode)
                    .frame(width: 130)
                Button("Hinzufügen") { addMapping() }
                    .disabled(selectedBundleID.isEmpty)
            }

            Text("Es werden nur aktuell geöffnete Apps angezeigt.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            runningApps = NSWorkspaceAppDetector.runningApps(excluding: Set(settings.correction.appMapping.keys))
        }
    }

    private func addMapping() {
        guard !selectedBundleID.isEmpty else { return }
        settings.correction.appMapping[selectedBundleID] = newMode
        selectedBundleID = ""
    }
}

struct ContextModePicker: View {
    let label: String
    @Binding var selection: ContextMode

    var body: some View {
        Picker(label, selection: $selection) {
            Text("Formell").tag(ContextMode.formal)
            Text("Informell").tag(ContextMode.informal)
            Text("Neutral").tag(ContextMode.neutral)
        }
    }
}
