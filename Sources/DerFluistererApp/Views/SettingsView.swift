import AppKit
import SwiftUI
import DerFluisterer

struct SettingsView: View {
    @Bindable var settings: SettingsManager
    var updater: SparkleUpdater?

    var body: some View {
        ScrollView {
            Form {
                GeneralSettingsSection(settings: settings)
                UpdateSettingsSection(settings: settings, updater: updater)
                AudioSettingsSection(settings: settings)
                CorrectionSettingsSection(settings: settings)
                APIKeySettingsSection(settings: settings)
                DictionarySettingsSection(settings: settings)
            }
            .formStyle(.grouped)
            .padding()
        }
    }
}

// MARK: - General

struct GeneralSettingsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section("Hotkey") {
            Picker("Taste", selection: $settings.hotkey.keyCode) {
                ForEach(HotkeyDisplayNames.selectableKeys, id: \.keyCode) { hotkey in
                    Text(hotkey.name).tag(hotkey.keyCode)
                }
            }

            Toggle("Halten zum Aufnehmen", isOn: $settings.hotkey.requiresHold)

            Text("Hotkey-Änderung wird nach Neustart der App wirksam.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("System") {
            Toggle("Bei Login starten", isOn: Binding(
                get: { settings.system.autoStart },
                set: { newValue in try? settings.setAutoStart(newValue) }
            ))

            Stepper(
                "History-Limit: \(settings.system.historyLimit)",
                value: $settings.system.historyLimit,
                in: 10...1000,
                step: 10
            )

            Toggle("Debug-Modus", isOn: $settings.system.debugMode)
        }
    }
}

// MARK: - Update

struct UpdateSettingsSection: View {
    @Bindable var settings: SettingsManager
    var updater: SparkleUpdater?

    var body: some View {
        Section("Updates") {
            Toggle("Automatisch nach Updates suchen", isOn: $settings.update.autoCheckEnabled)

            Toggle("Updates automatisch im Hintergrund installieren", isOn: $settings.update.silentAutoUpdate)
                .disabled(!settings.update.autoCheckEnabled)

            Button("Jetzt nach Updates suchen…") {
                updater?.checkForUpdates()
            }
            .disabled(updater?.canCheckForUpdates != true)

            if let warning = settings.feedUnreachableWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            LabeledContent("Update-Feed") {
                Text(SparkleUpdater.feedURL.absoluteString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Release Notes anzeigen") {
                NSWorkspace.shared.open(SparkleUpdater.releaseNotesURL)
            }
        }
    }
}

// MARK: - Audio

struct AudioSettingsSection: View {
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

        Section("Whisper-Modell") {
            Picker("Modell", selection: $settings.audio.whisperModel) {
                ForEach(WhisperModel.allCases, id: \.self) { model in
                    Text(model.displayName).tag(model)
                }
            }
            Text("Modell wird nach Auswahl automatisch neu geladen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Sprache") {
            Picker("Sprache", selection: $settings.audio.language) {
                Text("Deutsch").tag(SupportedLanguage.de)
                Text("English").tag(SupportedLanguage.en)
            }
            .pickerStyle(.segmented)
        }

        Section("Rauschunterdrückung") {
            Toggle("DeepFilterNet3", isOn: $settings.audio.noiseSuppressionEnabled)
            Text("Entfernt Hintergrundgeräusche in Echtzeit. Erfordert Neustart der Pipeline.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Feedback") {
            Toggle("Sounds aktiviert", isOn: $settings.audio.soundsEnabled)
        }
    }
}

// MARK: - Correction

struct CorrectionSettingsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section("Kontext-Modus") {
            Picker("Modus", selection: $settings.correction.contextMode) {
                Text("Formell").tag(ContextMode.formal)
                Text("Informell").tag(ContextMode.informal)
                Text("Neutral").tag(ContextMode.neutral)
                Text("Auto").tag(ContextMode.auto)
            }
            .pickerStyle(.segmented)
        }

        AppMappingSection(settings: settings)

        Section("Korrektur-Intensität") {
            Toggle("Umformulieren erlaubt", isOn: $settings.correction.allowRephrasing)
            Toggle("Kürzen erlaubt", isOn: $settings.correction.allowShortening)
            Toggle("Satzstruktur umstellen erlaubt", isOn: $settings.correction.allowRestructuring)
        }

        Section("LLM") {
            Stepper(
                "Timeout: \(settings.correction.llmTimeoutMs)ms",
                value: $settings.correction.llmTimeoutMs,
                in: 200...5000,
                step: 100
            )
        }
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

            Toggle("Hinweis bei fehlender Korrektur anzeigen", isOn: $settings.correction.showAPIKeyNotification)
                .font(.caption)
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

// MARK: - Dictionary

struct DictionarySettingsSection: View {
    @Bindable var settings: SettingsManager
    @State private var newTerm = ""

    var body: some View {
        Section("Persönliches Wörterbuch") {
            HStack {
                TextField("Neuer Begriff", text: $newTerm)
                    .onSubmit { addTerm() }
                Button("Hinzufügen") { addTerm() }
                    .disabled(newTerm.isEmpty)
            }

            if settings.correction.personalDictionary.isEmpty {
                Text("Noch keine Begriffe hinzugefügt")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(settings.correction.personalDictionary, id: \.self) { term in
                        HStack {
                            Text(term)
                            Spacer()
                            Button(role: .destructive) {
                                settings.correction.personalDictionary.removeAll { $0 == term }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 150)
            }
        }
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !settings.correction.personalDictionary.contains(trimmed) else { return }
        settings.correction.personalDictionary.append(trimmed)
        newTerm = ""
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
