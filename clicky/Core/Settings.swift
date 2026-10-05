import Foundation
import Combine

/// A modifier key that can be used as a push-to-talk trigger.
enum TriggerKey: String, CaseIterable, Identifiable, Codable {
    case option
    case control
    case command
    case function

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .option: return "Option ⌥"
        case .control: return "Control ⌃"
        case .command: return "Command ⌘"
        case .function: return "Globe/fn"
        }
    }

    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .control: return "⌃"
        case .command: return "⌘"
        case .function: return "fn"
        }
    }
}

/// Which speech-to-text engine records your voice.
enum STTEngine: String, CaseIterable, Identifiable, Codable {
    case apple
    case groqWhisper
    case localCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple on-device (free, offline)"
        case .groqWhisper: return "Groq Whisper (free tier)"
        case .localCommand: return "Local command (whisper.cpp, etc.)"
        }
    }
}

/// Which voice speaks replies back.
enum TTSEngine: String, CaseIterable, Identifiable, Codable {
    case system
    case edge
    case piper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "macOS system voice (free, offline)"
        case .edge: return "Edge TTS (free, no key)"
        case .piper: return "Piper local (free, offline)"
        }
    }
}

/// An OpenAI-compatible chat-completions endpoint. Every provider below
/// speaks the same shape, so free keys (Groq, Gemini, OpenRouter) and local
/// servers (Ollama, Hermes API server) work with zero extra code.
enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case openAI
    case openRouter
    case groq
    case gemini
    case ollama
    case hermesProxy
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .openRouter: return "OpenRouter (free :free models)"
        case .groq: return "Groq (free tier)"
        case .gemini: return "Gemini (free AI Studio key)"
        case .ollama: return "Ollama (local, no key)"
        case .hermesProxy: return "Hermes API server (local)"
        case .custom: return "Custom OpenAI-compatible"
        }
    }

    /// Default chat-completions URL. Empty baseURL in Settings means this.
    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1/chat/completions"
        case .openRouter: return "https://openrouter.ai/api/v1/chat/completions"
        case .groq: return "https://api.groq.com/openai/v1/chat/completions"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .ollama: return "http://localhost:11434/v1/chat/completions"
        case .hermesProxy: return "http://localhost:8000/v1/chat/completions"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o"
        case .openRouter: return "qwen/qwen2.5-vl-72b-instruct:free"
        case .groq: return "meta-llama/llama-4-scout-17b-16e-instruct"
        case .gemini: return "gemini-2.5-flash"
        case .ollama: return "qwen2.5vl"
        case .hermesProxy: return "hermes-default"
        case .custom: return ""
        }
    }

    /// Local endpoints work with no key.
    var requiresKey: Bool {
        switch self {
        case .ollama, .hermesProxy: return false
        default: return true
        }
    }

    /// Which ~/.hermes/.env key to copy from, if the user already has Hermes.
    var hermesEnvHint: String {
        switch self {
        case .groq: return "GROQ_API_KEY"
        case .gemini: return "GEMINI_API_KEY"
        case .openRouter: return "OPENROUTER_API_KEY"
        case .openAI: return "OPENAI_API_KEY"
        default: return ""
        }
    }
}

/// Persisted user preferences, backed by `UserDefaults`. API keys live in the
/// Keychain, not here.
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var dictateTrigger: TriggerKey {
        didSet { defaults.set(dictateTrigger.rawValue, forKey: Keys.dictateTrigger) }
    }
    @Published var agentTrigger: TriggerKey {
        didSet { defaults.set(agentTrigger.rawValue, forKey: Keys.agentTrigger) }
    }
    @Published var provider: LLMProvider {
        didSet {
            defaults.set(provider.rawValue, forKey: Keys.provider)
            // Snap model/baseURL to the new provider's defaults when the user
            // hasn't customized them, so switching provider just works.
            if model.isEmpty || LLMProvider.allCases.map(\.defaultModel).contains(model) {
                model = provider.defaultModel
            }
            if baseURL.isEmpty || LLMProvider.allCases.map(\.defaultBaseURL).contains(baseURL) {
                baseURL = ""
            }
        }
    }
    @Published var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Keys.baseURL) }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }
    @Published var localeIdentifier: String {
        didSet { defaults.set(localeIdentifier, forKey: Keys.locale) }
    }
    @Published var includeScreenshot: Bool {
        didSet { defaults.set(includeScreenshot, forKey: Keys.includeScreenshot) }
    }
    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }
    @Published var showOnboarding: Bool {
        didSet { defaults.set(showOnboarding, forKey: Keys.showOnboarding) }
    }

    // MARK: - Free voice replies (on-device, no ElevenLabs)

    /// Speak agent-mode replies aloud with AVSpeechSynthesizer. $0, offline.
    @Published var voiceReply: Bool {
        didSet { defaults.set(voiceReply, forKey: Keys.voiceReply) }
    }
    /// Speak sentence-by-sentence while tokens stream in (~1s to first word).
    @Published var streamVoice: Bool {
        didSet { defaults.set(streamVoice, forKey: Keys.streamVoice) }
    }
    /// AVSpeechUtterance rate 0.0...1.0.
    @Published var speechRate: Double {
        didSet { defaults.set(speechRate, forKey: Keys.speechRate) }
    }
    /// AVSpeechUtterance pitch 0.5...2.0. Piper ignores this.
    @Published var speechPitch: Double {
        didSet { defaults.set(speechPitch, forKey: Keys.speechPitch) }
    }
    /// AVSpeechSynthesisVoice identifier. Empty = system default.
    @Published var voiceIdentifier: String {
        didSet { defaults.set(voiceIdentifier, forKey: Keys.voiceIdentifier) }
    }

    // MARK: - Voice tab: engines are per-user, local-only, never synced.

    @Published var sttEngine: STTEngine {
        didSet { defaults.set(sttEngine.rawValue, forKey: Keys.sttEngine) }
    }
    /// Groq transcription model.
    @Published var groqSTTModel: String {
        didSet { defaults.set(groqSTTModel, forKey: Keys.groqSTTModel) }
    }
    /// Shell template for local STT. `{audio}` = recorded WAV path.
    /// Stdout is used as the transcript.
    @Published var localSTTCommand: String {
        didSet { defaults.set(localSTTCommand, forKey: Keys.localSTTCommand) }
    }
    @Published var ttsEngine: TTSEngine {
        didSet { defaults.set(ttsEngine.rawValue, forKey: Keys.ttsEngine) }
    }
    /// Edge voice, e.g. en-US-AriaNeural. 322 voices, 74 languages.
    @Published var edgeVoice: String {
        didSet { defaults.set(edgeVoice, forKey: Keys.edgeVoice) }
    }
    /// `edge-tts` executable name or absolute path.
    @Published var edgeBinary: String {
        didSet { defaults.set(edgeBinary, forKey: Keys.edgeBinary) }
    }
    /// `piper` executable name or absolute path.
    @Published var piperBinary: String {
        didSet { defaults.set(piperBinary, forKey: Keys.piperBinary) }
    }
    /// Absolute path to a Piper voice model (.onnx).
    @Published var piperModel: String {
        didSet { defaults.set(piperModel, forKey: Keys.piperModel) }
    }
    /// Piper speaker index. -1 omits --speaker (single-speaker voices).
    @Published var piperSpeaker: Int {
        didSet { defaults.set(piperSpeaker, forKey: Keys.piperSpeaker) }
    }

    // MARK: - Conversation: hands-free behaviour.

    /// After a reply, listen again automatically (wake-word sessions).
    @Published var continuousMode: Bool {
        didSet { defaults.set(continuousMode, forKey: Keys.continuousMode) }
    }
    /// Auto-finish listening after this many seconds of silence.
    /// Needed hands-free; harmless for push-to-talk.
    @Published var silenceDuration: Double {
        didSet { defaults.set(silenceDuration, forKey: Keys.silenceDuration) }
    }
    @Published var silenceAutoStop: Bool {
        didSet { defaults.set(silenceAutoStop, forKey: Keys.silenceAutoStop) }
    }
    /// Saying exactly this (case-insensitive) ends a hands-free session.
    /// Empty disables.
    @Published var stopPhrase: String {
        didSet { defaults.set(stopPhrase, forKey: Keys.stopPhrase) }
    }

    // MARK: - Wake word: fully hands-free, opt-in (mic indicator stays on).

    @Published var wakeEnabled: Bool {
        didSet { defaults.set(wakeEnabled, forKey: Keys.wakeEnabled) }
    }
    /// Custom name to listen for, e.g. "hey clicky" or "jarvis".
    @Published var wakePhrase: String {
        didSet { defaults.set(wakePhrase, forKey: Keys.wakePhrase) }
    }

    /// API key for the current LLM provider, stored in the Keychain.
    /// Each provider has its own slot, so Groq and Gemini keys never collide.
    var apiKey: String {
        get { apiKey(for: provider) }
        set {
            setApiKey(newValue, for: provider)
            objectWillChange.send()
        }
    }

    /// Groq key in its own slot. Used by Groq Whisper STT even when the LLM
    /// provider is something else (Ollama, Hermes, …).
    var groqKey: String {
        get { apiKey(for: .groq) }
        set {
            setApiKey(newValue, for: .groq)
            objectWillChange.send()
        }
    }

    func apiKey(for p: LLMProvider) -> String {
        let slot = Keys.keySlot(for: p)
        if let v = Keychain.shared.string(for: slot), !v.isEmpty { return v }
        // Migrate once from the old shared slots.
        if let v = Keychain.shared.string(for: Keys.apiKey), !v.isEmpty { return v }
        return Keychain.shared.string(for: Keys.legacyOpenAIKey) ?? ""
    }

    func setApiKey(_ value: String, for p: LLMProvider) {
        let slot = Keys.keySlot(for: p)
        if value.isEmpty {
            Keychain.shared.delete(slot)
        } else {
            Keychain.shared.set(value, for: slot)
        }
    }

    var hasAPIKey: Bool { !provider.requiresKey || !apiKey.isEmpty }

    /// Resolved chat-completions endpoint: custom baseURL or provider default.
    var resolvedEndpoint: URL {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty, let u = URL(string: raw) { return u }
        if let u = URL(string: provider.defaultBaseURL) { return u }
        return URL(string: "https://api.openai.com/v1/chat/completions")!
    }

    /// Build the LLM client for the current provider settings.
    func makeLLMClient() -> LLMProviding {
        guard hasAPIKey else { return EchoLLM() }
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return OpenAIClient(
            apiKey: apiKey,
            model: m.isEmpty ? provider.defaultModel : m,
            baseURL: resolvedEndpoint
        )
    }

    init() {
        dictateTrigger = TriggerKey(rawValue: defaults.string(forKey: Keys.dictateTrigger) ?? "") ?? .function
        agentTrigger = TriggerKey(rawValue: defaults.string(forKey: Keys.agentTrigger) ?? "") ?? .option
        let storedProvider = defaults.string(forKey: Keys.provider).flatMap(LLMProvider.init(rawValue:))
        provider = storedProvider ?? .openAI
        baseURL = defaults.string(forKey: Keys.baseURL) ?? ""
        // Migrate old installs: keep their model, else provider default.
        if let stored = defaults.string(forKey: Keys.model), !stored.isEmpty {
            model = stored
        } else {
            model = (storedProvider == nil) ? "gpt-4o" : provider.defaultModel
        }
        localeIdentifier = defaults.string(forKey: Keys.locale) ?? "en-US"
        includeScreenshot = defaults.object(forKey: Keys.includeScreenshot) as? Bool ?? true
        playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
        showOnboarding = defaults.object(forKey: Keys.showOnboarding) as? Bool ?? true
        voiceReply = defaults.object(forKey: Keys.voiceReply) as? Bool ?? true
        streamVoice = defaults.object(forKey: Keys.streamVoice) as? Bool ?? true
        let storedRate = defaults.object(forKey: Keys.speechRate) as? Double
        speechRate = storedRate ?? 0.5
        let storedPitch = defaults.object(forKey: Keys.speechPitch) as? Double
        speechPitch = storedPitch ?? 1.0
        voiceIdentifier = defaults.string(forKey: Keys.voiceIdentifier) ?? ""
        sttEngine = STTEngine(rawValue: defaults.string(forKey: Keys.sttEngine) ?? "") ?? .apple
        groqSTTModel = defaults.string(forKey: Keys.groqSTTModel) ?? "whisper-large-v3-turbo"
        localSTTCommand = defaults.string(forKey: Keys.localSTTCommand) ?? ""
        ttsEngine = TTSEngine(rawValue: defaults.string(forKey: Keys.ttsEngine) ?? "") ?? .system
        edgeVoice = defaults.string(forKey: Keys.edgeVoice) ?? "en-US-AriaNeural"
        edgeBinary = defaults.string(forKey: Keys.edgeBinary) ?? "edge-tts"
        piperBinary = defaults.string(forKey: Keys.piperBinary) ?? "piper"
        piperModel = defaults.string(forKey: Keys.piperModel) ?? ""
        piperSpeaker = defaults.object(forKey: Keys.piperSpeaker) as? Int ?? -1
        continuousMode = defaults.object(forKey: Keys.continuousMode) as? Bool ?? false
        let storedSilence = defaults.object(forKey: Keys.silenceDuration) as? Double
        silenceDuration = storedSilence ?? 2.5
        silenceAutoStop = defaults.object(forKey: Keys.silenceAutoStop) as? Bool ?? true
        stopPhrase = defaults.string(forKey: Keys.stopPhrase) ?? "stop"
        wakeEnabled = defaults.object(forKey: Keys.wakeEnabled) as? Bool ?? false
        let storedWake = defaults.string(forKey: Keys.wakePhrase)
        wakePhrase = (storedWake?.isEmpty == false) ? storedWake! : "hey clicky"
    }

    private enum Keys {
        static let dictateTrigger = "dictateTrigger"
        static let agentTrigger = "agentTrigger"
        static let provider = "llmProvider"
        static let baseURL = "llmBaseURL"
        static let model = "model"
        static let locale = "localeIdentifier"
        static let includeScreenshot = "includeScreenshot"
        static let playSounds = "playSounds"
        static let showOnboarding = "showOnboarding"
        static let voiceReply = "voiceReply"
        static let streamVoice = "streamVoice"
        static let speechRate = "speechRate"
        static let speechPitch = "speechPitch"
        static let voiceIdentifier = "voiceIdentifier"
        static let sttEngine = "sttEngine"
        static let groqSTTModel = "groqSTTModel"
        static let localSTTCommand = "localSTTCommand"
        static let ttsEngine = "ttsEngine"
        static let edgeVoice = "edgeVoice"
        static let edgeBinary = "edgeBinary"
        static let piperBinary = "piperBinary"
        static let piperModel = "piperModel"
        static let piperSpeaker = "piperSpeaker"
        static let continuousMode = "continuousMode"
        static let silenceDuration = "silenceDuration"
        static let silenceAutoStop = "silenceAutoStop"
        static let stopPhrase = "stopPhrase"
        static let wakeEnabled = "wakeEnabled"
        static let wakePhrase = "wakePhrase"
        static let apiKey = "llm.apiKey"
        static let legacyOpenAIKey = "openai.apiKey"

        /// Per-provider Keychain slot so keys never collide.
        static func keySlot(for p: LLMProvider) -> String {
            "llm.\(p.rawValue).apiKey"
        }
    }
}
