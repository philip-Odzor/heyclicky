import AppKit
import AVFoundation
import SwiftUI

/// Preferences: API key, triggers, language, skills.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            VoiceSettings()
                .tabItem { Label("Voice", systemImage: "waveform") }
            SkillsSettings()
                .tabItem { Label("Skills", systemImage: "sparkles") }
            PermissionsSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .environmentObject(appState)
        .padding(20)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""

    var body: some View {
        Form {
            Section("Model — any OpenAI-compatible endpoint (free keys OK)") {
                Picker("Provider", selection: Binding(
                    get: { appState.settings.provider },
                    set: { appState.settings.provider = $0 }
                )) {
                    ForEach(LLMProvider.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("Base URL (empty = provider default)", text: Binding(
                    get: { appState.settings.baseURL },
                    set: { appState.settings.baseURL = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                Text("Default: \(appState.settings.provider.defaultBaseURL.isEmpty ? "—" : appState.settings.provider.defaultBaseURL)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if appState.settings.provider.requiresKey {
                    SecureField("API key", text: $apiKey)
                        .onAppear { apiKey = appState.settings.apiKey }
                        .onChange(of: apiKey) { _, newValue in
                            appState.settings.apiKey = newValue
                        }
                        .onChange(of: appState.settings.provider) { _, _ in
                            apiKey = appState.settings.apiKey
                        }
                    if !appState.settings.provider.hermesEnvHint.isEmpty {
                        Text("Reuse from ~/.hermes/.env: \(appState.settings.provider.hermesEnvHint)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No key needed — runs on your machine.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("API key (optional)", text: $apiKey)
                        .onAppear { apiKey = appState.settings.apiKey }
                        .onChange(of: apiKey) { _, newValue in
                            appState.settings.apiKey = newValue
                        }
                }
                TextField("Model", text: Binding(
                    get: { appState.settings.model },
                    set: { appState.settings.model = $0 }
                ))
                Text("Default: \(appState.settings.provider.defaultModel). Used only for screen-aware writing. Dictation runs on-device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Triggers") {
                Picker("Dictate (raw text)", selection: Binding(
                    get: { appState.settings.dictateTrigger },
                    set: { appState.settings.dictateTrigger = $0 }
                )) {
                    ForEach(TriggerKey.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Write with screen", selection: Binding(
                    get: { appState.settings.agentTrigger },
                    set: { appState.settings.agentTrigger = $0 }
                )) {
                    ForEach(TriggerKey.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Hold to talk, release to run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Send a screenshot as context", isOn: Binding(
                    get: { appState.settings.includeScreenshot },
                    set: { appState.settings.includeScreenshot = $0 }
                ))
                Toggle("Play sounds", isOn: Binding(
                    get: { appState.settings.playSounds },
                    set: { appState.settings.playSounds = $0 }
                ))
                Text("Dictation language lives in Settings → Voice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct VoiceSettings: View {
    @EnvironmentObject var appState: AppState
    @State private var groqKey: String = ""
    @State private var sttCheck: String = ""
    @State private var showSttCheck = false
    @State private var ttsError: String = ""
    @State private var showTtsError = false

    /// Common speech locales. A stored custom value is kept as an extra row.
    private var localeOptions: [(code: String, label: String)] {
        var base = [
            ("en-US", "English (US)"), ("en-GB", "English (UK)"),
            ("en-AU", "English (Australia)"), ("de-DE", "Deutsch"),
            ("fr-FR", "Français"), ("es-ES", "Español (España)"),
            ("it-IT", "Italiano"), ("pt-BR", "Português (Brasil)"),
            ("nl-NL", "Nederlands"), ("ja-JP", "日本語"),
            ("zh-CN", "中文 (简体)"), ("zh-TW", "中文 (繁體)"),
            ("ko-KR", "한국어"), ("ru-RU", "Русский"),
            ("ar-SA", "العربية"), ("hi-IN", "हिन्दी"),
        ]
        let current = appState.settings.localeIdentifier
        if !current.isEmpty, !base.map(\.0).contains(current) {
            base.append((current, "\(current) (custom)"))
        }
        return base
    }

    private var systemVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Form {
            Section("Speech to text — how clicky hears you") {
                Picker("Engine", selection: Binding(
                    get: { appState.settings.sttEngine },
                    set: { appState.settings.sttEngine = $0 }
                )) {
                    ForEach(STTEngine.allCases) { Text($0.displayName).tag($0) }
                }
                if appState.settings.sttEngine == .groqWhisper {
                    SecureField("Groq key", text: $groqKey)
                        .onAppear { groqKey = appState.settings.groqKey }
                        .onChange(of: groqKey) { _, newValue in
                            appState.settings.groqKey = newValue
                        }
                    Text("Free tier. Reuse GROQ_API_KEY from ~/.hermes/.env.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Model", text: Binding(
                        get: { appState.settings.groqSTTModel },
                        set: { appState.settings.groqSTTModel = $0 }
                    ))
                }
                if appState.settings.sttEngine == .localCommand {
                    TextField("Command", text: Binding(
                        get: { appState.settings.localSTTCommand },
                        set: { appState.settings.localSTTCommand = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text("Use {audio} for the recorded WAV. Stdout is the transcript. Example: whisper-cli -m ~/models/ggml-base.en.bin -f {audio} -otxt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Language", selection: Binding(
                    get: { appState.settings.localeIdentifier },
                    set: { appState.settings.localeIdentifier = $0 }
                )) {
                    ForEach(localeOptions, id: \.code) { option in
                        Text(option.label).tag(option.code)
                    }
                }
                Button("Check setup") {
                    sttCheck = sttDiagnostics()
                    showSttCheck = true
                }
                .alert("Speech-to-text check", isPresented: $showSttCheck) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(sttCheck)
                }
            }

            Section("Speech out — how clicky talks back (no ElevenLabs)") {
                Picker("Engine", selection: Binding(
                    get: { appState.settings.ttsEngine },
                    set: { appState.settings.ttsEngine = $0 }
                )) {
                    ForEach(TTSEngine.allCases) { Text($0.displayName).tag($0) }
                }
                if appState.settings.ttsEngine == .system {
                    Picker("Voice", selection: Binding(
                        get: { appState.settings.voiceIdentifier },
                        set: { appState.settings.voiceIdentifier = $0 }
                    )) {
                        Text("System default").tag("")
                        ForEach(systemVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                        }
                    }
                }
                if appState.settings.ttsEngine == .edge {
                    TextField("Voice", text: Binding(
                        get: { appState.settings.edgeVoice },
                        set: { appState.settings.edgeVoice = $0 }
                    ))
                    Text("322 voices, 74 languages. Try en-US-AriaNeural, en-US-GuyNeural, en-GB-SoniaNeural.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Binary", text: Binding(
                        get: { appState.settings.edgeBinary },
                        set: { appState.settings.edgeBinary = $0 }
                    ))
                    Text("Install with: pip install edge-tts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if appState.settings.ttsEngine == .piper {
                    TextField("Binary", text: Binding(
                        get: { appState.settings.piperBinary },
                        set: { appState.settings.piperBinary = $0 }
                    ))
                    TextField("Voice model (.onnx path)", text: Binding(
                        get: { appState.settings.piperModel },
                        set: { appState.settings.piperModel = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Stepper("Speaker: \(appState.settings.piperSpeaker < 0 ? "default" : String(appState.settings.piperSpeaker))", value: Binding(
                        get: { appState.settings.piperSpeaker },
                        set: { appState.settings.piperSpeaker = $0 }
                    ), in: -1...20)
                    Text("Install with: pip install piper-tts. Voices: huggingface.co/rhasspy/piper-voices. -1 omits --speaker (single-speaker voices).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Rate")
                    Slider(value: Binding(
                        get: { appState.settings.speechRate },
                        set: { appState.settings.speechRate = $0 }
                    ), in: 0.3...1.0)
                }
                HStack {
                    Text("Pitch")
                    Slider(value: Binding(
                        get: { appState.settings.speechPitch },
                        set: { appState.settings.speechPitch = $0 }
                    ), in: 0.5...2.0)
                    Text("(system + Edge; Piper ignores pitch)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Test voice") {
                    Task { await testVoice() }
                }
                .alert("Voice test failed", isPresented: $showTtsError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(ttsError)
                }
            }

            Section("Conversation — hands-free behaviour") {
                Toggle("Speak replies aloud", isOn: Binding(
                    get: { appState.settings.voiceReply },
                    set: { appState.settings.voiceReply = $0 }
                ))
                Toggle("Speak as it generates (streaming)", isOn: Binding(
                    get: { appState.settings.streamVoice },
                    set: { appState.settings.streamVoice = $0 }
                ))
                Toggle("Keep listening after each reply", isOn: Binding(
                    get: { appState.settings.continuousMode },
                    set: { appState.settings.continuousMode = $0 }
                ))
                Text("Wake-word sessions loop until the stop phrase. Push-to-talk is unaffected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Stop on silence", isOn: Binding(
                    get: { appState.settings.silenceAutoStop },
                    set: { appState.settings.silenceAutoStop = $0 }
                ))
                HStack {
                    Text("Silence")
                    Slider(value: Binding(
                        get: { appState.settings.silenceDuration },
                        set: { appState.settings.silenceDuration = $0 }
                    ), in: 1.0...5.0, step: 0.5)
                    Text("\(appState.settings.silenceDuration, specifier: "%.1f")s")
                        .font(.caption)
                        .frame(width: 40)
                }
                TextField("Stop phrase", text: Binding(
                    get: { appState.settings.stopPhrase },
                    set: { appState.settings.stopPhrase = $0 }
                ))
                Text("Saying exactly this ends a hands-free session. Empty disables.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Wake word — fully hands-free (opt-in)") {
                Toggle("Listen for my wake phrase", isOn: Binding(
                    get: { appState.settings.wakeEnabled },
                    set: { appState.settings.wakeEnabled = $0 }
                ))
                TextField("Phrase", text: Binding(
                    get: { appState.settings.wakePhrase },
                    set: { appState.settings.wakePhrase = $0 }
                ))
                Text(appState.wakeListening
                     ? "Listening now — say “\(appState.settings.wakePhrase)” to start. The mic indicator stays on while listening."
                     : "Off. Hotkeys keep working either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The listener pauses itself during every dictation run, so it never fights the mic. Say the stop phrase or press Esc to end.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func sttDiagnostics() -> String {
        switch appState.settings.sttEngine {
        case .apple:
            return "Apple on-device dictation needs Microphone + Speech Recognition permission (Settings → Permissions). No key, no network."
        case .groqWhisper:
            if appState.settings.groqKey.isEmpty {
                return "Missing Groq key. Paste GROQ_API_KEY above (free tier)."
            }
            return "Groq Whisper ready (model \(appState.settings.groqSTTModel)). Audio records locally, uploads on release."
        case .localCommand:
            if appState.settings.localSTTCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Set a command first. {audio} is replaced with the recorded WAV; stdout is the transcript."
            }
            return "Local command configured. Audio records locally, the command runs on release."
        }
    }

    private func testVoice() async {
        let settings = appState.settings
        do {
            switch settings.ttsEngine {
            case .system:
                VoiceOutput().speak("Hello from clicky.", settings: settings)
            case .edge:
                let speaker = EdgeTTSSpeaker()
                speaker.binary = settings.edgeBinary
                speaker.voice = settings.edgeVoice.isEmpty ? "en-US-AriaNeural" : settings.edgeVoice
                speaker.rate = settings.speechRate
                speaker.pitch = settings.speechPitch
                try await speaker.speak(text: "Hello from clicky.")
            case .piper:
                let speaker = PiperTTSSpeaker()
                speaker.binary = settings.piperBinary
                speaker.modelPath = settings.piperModel
                speaker.speaker = settings.piperSpeaker
                speaker.rate = settings.speechRate
                try await speaker.speak(text: "Hello from clicky.")
            }
        } catch {
            let message = error.localizedDescription
            await MainActor.run {
                ttsError = message
                showTtsError = true
            }
        }
    }
}

private struct SkillsSettings: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skills are markdown files that steer clicky for a task.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(appState.skills.skills) { skill in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(skill.name).fontWeight(.medium)
                            if !skill.appMatch.isEmpty {
                                Text(skill.appMatch.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { skill.enabled },
                            set: { appState.skills.setEnabled($0, for: skill) }
                        ))
                        .labelsHidden()
                    }
                }
            }

            HStack {
                Button("Open Skills Folder") {
                    NSWorkspace.shared.open(appState.skills.directoryURL)
                }
                Button("Reload") { appState.skills.reload() }
                Spacer()
            }
        }
    }
}

private struct PermissionsSettings: View {
    var body: some View {
        Form {
            Section("clicky needs a few permissions") {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Global hotkeys + pasting the result.",
                    action: Permissions.openAccessibilitySettings
                )
                PermissionRow(
                    title: "Screen Recording",
                    detail: "See your screen for context.",
                    action: Permissions.openScreenRecordingSettings
                )
                PermissionRow(
                    title: "Microphone",
                    detail: "Hear what you say.",
                    action: Permissions.openMicrophoneSettings
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings", action: action)
        }
    }
}
