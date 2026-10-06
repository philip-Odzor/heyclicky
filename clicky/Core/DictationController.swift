import AppKit

/// Orchestrates a single dictation: show the pill, record, transcribe, and
/// either insert the raw transcript (dictate mode) or ask the model to write
/// screen-aware text (agent mode).
@MainActor
final class DictationController {
    private unowned let appState: AppState
    private let engine = DictationEngine()
    private let voice = VoiceOutput()
    private var mode: DictationMode = .dictate
    private var context: FrontmostApp = .unknown
    private var runToken = 0
    /// True when this session started hands-free (wake word / continuous).
    private var handsFree = false
    private var silentStreak = 0
    private var listenGen = 0

    init(appState: AppState) {
        self.appState = appState
    }

    /// Requests up-front permissions so the first real use isn't blocked.
    func prepare() async {
        engine.updateLocale(appState.settings.localeIdentifier)
        _ = await engine.requestAuthorization()
    }

    func begin(mode: DictationMode, handsFree: Bool = false, bargeIn: Bool = true) {
        // Barge-in: a new hold from thinking/writing/done/error cancels the
        // in-flight reply (runToken) and interrupts spoken audio.
        switch appState.phase {
        case .idle, .done, .error, .thinking, .writing:
            break
        default:
            return
        }

        self.mode = mode
        self.handsFree = handsFree
        runToken += 1
        listenGen += 1
        // A new explicit run clears the boss-key hide.
        appState.stealthHidden = false
        // A new hold interrupts any spoken reply (barge-in). Chained
        // continuous listens keep the reply playing underneath.
        if bargeIn { voice.stop() }

        // Capture the app the user was in *before* our pill grabs any focus.
        context = FrontmostAppObserver.current()
        appState.contextAppName = context.name
        appState.contextAppIcon = context.icon
        appState.transcript = ""

        engine.updateLocale(appState.settings.localeIdentifier)
        configureEngineForCurrentSettings()
        engine.onLevel = { [weak self] level in self?.pushLevel(level) }

        guard Permissions.accessibilityAuthorized(prompt: true) else {
            fail("Enable Accessibility for clicky in System Settings to use hotkeys.")
            return
        }

        do {
            try engine.start()
            appState.phase = .listening
            appState.pill?.show(mode: mode)
            if appState.settings.soundsAllowed { Sounds.start() }
            // Hands-free has no key release to end on: auto-finish on silence.
            if appState.settings.silenceAutoStop {
                startSilenceWatchdog()
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Hands-free entry point used by the wake word ("hey clicky", …).
    func beginHandsFree(mode: DictationMode = .agent) {
        begin(mode: mode, handsFree: true)
    }

    /// Push the current Voice-tab STT settings into the engine.
    private func configureEngineForCurrentSettings() {
        let s = appState.settings
        engine.sttEngine = s.sttEngine
        engine.groqAPIKey = s.groqKey
        engine.groqModel = s.groqSTTModel
        // "en-US" -> "en" for Whisper; empty stays empty (auto-detect).
        let locale = s.localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        engine.groqLanguage = locale.count >= 2 ? String(locale.prefix(2)).lowercased() : ""
        engine.localSTTCommand = s.localSTTCommand
    }

    /// Auto-finish after `silenceDuration` of quiet mic. Cancelled by any
    /// newer listen (listenGen), finish, or cancel.
    private func startSilenceWatchdog() {
        listenGen += 1
        let gen = listenGen
        let threshold: Float = 0.12
        let started = Date()
        var lastLoud = Date()
        let minUtterance: TimeInterval = 1.2
        Task { @MainActor in
            while gen == self.listenGen, self.appState.phase == .listening {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard gen == self.listenGen else { return }
                if self.engine.level > threshold { lastLoud = Date() }
                let elapsed = Date().timeIntervalSince(started)
                let silentFor = Date().timeIntervalSince(lastLoud)
                if elapsed > minUtterance, silentFor >= self.appState.settings.silenceDuration {
                    self.finish()
                    return
                }
            }
        }
    }

    func finish() {
        guard appState.phase == .listening else { return }
        listenGen += 1 // stop the silence watchdog; this run owns the rest.
        // Starting your turn cuts the previous reply (barge-in).
        voice.stop()
        let token = runToken
        let wasHandsFree = handsFree
        Task {
            let transcript: String
            do {
                transcript = try await engine.stop()
            } catch {
                guard token == runToken else { return }
                fail(error.localizedDescription)
                return
            }
            appState.transcript = transcript
            guard token == runToken else { return }

            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            // Stop phrase ends a hands-free session ("stop", "goodbye", …).
            let stopWord = appState.settings.stopPhrase
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !stopWord.isEmpty, trimmed.lowercased() == stopWord {
                endHandsFree()
                return
            }
            guard !trimmed.isEmpty else {
                // Hands-free: a few silent turns end the session instead of
                // erroring every time the room is quiet.
                if wasHandsFree {
                    silentStreak += 1
                    if silentStreak >= 3 {
                        endHandsFree()
                    } else {
                        begin(mode: .agent, handsFree: true, bargeIn: false)
                    }
                } else {
                    fail("I didn't catch that.")
                }
                return
            }
            silentStreak = 0

            switch mode {
            case .dictate:
                complete(with: trimmed, speak: false)
            case .agent:
                await runAgent(instruction: trimmed, token: token)
            }
        }
    }

    func cancel() {
        runToken += 1
        listenGen += 1
        handsFree = false
        silentStreak = 0
        engine.abort()
        voice.stop()
        appState.phase = .idle
        appState.pill?.hide()
    }

    private func endHandsFree() {
        runToken += 1
        listenGen += 1
        handsFree = false
        silentStreak = 0
        voice.stop()
        appState.phase = .idle
        appState.pill?.hide()
    }

    // MARK: - Agent mode

    private func runAgent(instruction: String, token: Int) async {
        appState.phase = .thinking
        appState.pill?.update()

        let screenshot: Data? = appState.settings.includeScreenshot
            ? await ScreenContextProvider.captureScreenshotJPEG()
            : nil

        let memories: [String] = appState.settings.memoryEnabled
            ? appState.memory.recall(for: instruction)
            : []
        let request = WriteRequest(
            instruction: instruction,
            app: context,
            screenshotJPEG: screenshot,
            skills: appState.skills.skills(for: context),
            memories: memories
        )

        let client: LLMProviding = appState.settings.makeLLMClient()

        do {
            // Realtime feel with $0 infra: speak sentence-by-sentence while
            // tokens stream in, instead of waiting for the full reply.
            if appState.settings.voiceReply && appState.settings.streamVoice {
                let result = try await client.writeStreaming(request) { [weak self] sentence in
                    Task { @MainActor in
                        guard let self, self.runToken == token else { return }
                        if self.appState.phase != .writing {
                            self.appState.phase = .writing
                            self.appState.pill?.update()
                        }
                        self.speakNow(sentence)
                    }
                }
                guard token == runToken else { return }
                appState.phase = .writing
                appState.pill?.update()
                try? await Task.sleep(nanoseconds: 150_000_000)
                // Already spoken chunk-by-chunk; just paste, don't re-speak.
                if appState.settings.memoryEnabled {
                    appState.memory.remember(instruction: instruction, output: result, app: context.name)
                }
                complete(with: result, speak: false)
                return
            }

            let result = try await client.write(request)
            guard token == runToken else { return }
            appState.phase = .writing
            appState.pill?.update()
            try? await Task.sleep(nanoseconds: 150_000_000)
            if appState.settings.memoryEnabled {
                appState.memory.remember(instruction: instruction, output: result, app: context.name)
            }
            complete(with: result, speak: appState.settings.voiceReply)
        } catch {
            guard token == runToken else { return }
            fail(error.localizedDescription)
        }
    }

    // MARK: - Completion

    private func speakNow(_ sentence: String) {
        voice.speakSentence(sentence, settings: appState.settings)
    }

    private func complete(with text: String, speak: Bool) {
        appState.lastResult = text
        TextInserter.insert(text)
        if speak && appState.settings.voiceReply {
            voice.speak(text, settings: appState.settings)
        }
        // Continuous hands-free conversation: listen again right away.
        // The hide timer below sees .listening and skips itself.
        if appState.settings.continuousMode, handsFree, mode == .agent {
            begin(mode: .agent, handsFree: true, bargeIn: false)
            return
        }
        handsFree = false
        silentStreak = 0
        appState.phase = .done
        if appState.settings.soundsAllowed { Sounds.done() }
        appState.pill?.update()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.appState.phase == .done else { return }
            self.appState.phase = .idle
            self.appState.pill?.hide()
        }
    }

    private func fail(_ message: String) {
        engine.abort()
        // A failed turn ends a hands-free chain (avoids error loops on a
        // bad key). The wake word can start a fresh session.
        handsFree = false
        silentStreak = 0
        appState.phase = .error(message)
        if appState.settings.soundsAllowed { Sounds.error() }
        appState.pill?.update()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self else { return }
            if case .error = self.appState.phase {
                self.appState.phase = .idle
                self.appState.pill?.hide()
            }
        }
    }

    private func pushLevel(_ level: Float) {
        var levels = appState.levels
        levels.removeFirst()
        levels.append(level)
        appState.levels = levels
    }
}

/// Tiny system-sound helper for start/done/error feedback.
enum Sounds {
    static func start() { NSSound(named: "Tink")?.play() }
    static func done() { NSSound(named: "Pop")?.play() }
    static func error() { NSSound(named: "Basso")?.play() }
}
