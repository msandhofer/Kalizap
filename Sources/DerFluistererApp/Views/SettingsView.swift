import SwiftUI
import DerFluisterer

struct SettingsView: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        ScrollView {
            Form {
                GeneralSettingsSection(settings: settings)
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
            Text("Hotkey-Konfiguration kommt in Issue #4")
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

// MARK: - Audio

struct AudioSettingsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section("Mikrofon") {
            Text("Mikrofon-Auswahl kommt in Issue #5")
                .foregroundStyle(.secondary)
        }

        Section("Sprache") {
            Picker("Sprache", selection: $settings.audio.language) {
                Text("Deutsch").tag(SupportedLanguage.de)
                Text("English").tag(SupportedLanguage.en)
            }
            .pickerStyle(.segmented)
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
        }
        .onAppear {
            apiKeyInput = (try? settings.resolveAPIKey()) ?? ""
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
