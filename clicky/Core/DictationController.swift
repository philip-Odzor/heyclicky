import AppKit

/// Orchestrates a single dictation: show the pill, record, transcribe, and
/// either insert the raw transcript (dictate mode) or ask the model to write
/// screen-aware text (agent mode).
@MainActor
final class DictationController {
    private unowned let appState: AppState
    private let engine = DictationEngine()
    private let speaker = SpeechResponder()
    private var mode: DictationMode = .dictate
    private var context: FrontmostApp = .unknown
    private var runToken = 0

    init(appState: AppState) {
        self.appState = appState
    }

    /// Requests up-front permissions so the first real use isn't blocked.
    func prepare() async {
        engine.updateLocale(appState.settings.localeIdentifier)
        _ = await engine.requestAuthorization()
    }

    func begin(mode: DictationMode) {
        // Barge-in: a new hold from thinking/writing/done/error cancels the
        // in-flight reply (runToken) and interrupts spoken audio.
        switch appState.phase {
        case .idle, .done, .error, .thinking, .writing:
            break
        default:
            return
        }

        self.mode = mode
        runToken += 1
        // Barge-in: a new hold interrupts any spoken reply.
        speaker.stop()

        // Capture the app the user was in *before* our pill grabs any focus.
        context = FrontmostAppObserver.current()
        appState.contextAppName = context.name
        appState.contextAppIcon = context.icon
        appState.transcript = ""

        engine.updateLocale(appState.settings.localeIdentifier)
        engine.onLevel = { [weak self] level in self?.pushLevel(level) }

        guard Permissions.accessibilityAuthorized(prompt: true) else {
            fail("Enable Accessibility for clicky in System Settings to use hotkeys.")
            return
        }

        do {
            try engine.start()
            appState.phase = .listening
            appState.pill?.show(mode: mode)
            if appState.settings.playSounds { Sounds.start() }
        } catch {
            fail(error.localizedDescription)
        }
    }

    func finish() {
        guard appState.phase == .listening else { return }
        let token = runToken
        Task {
            let transcript = await engine.stop()
            appState.transcript = transcript
            guard token == runToken else { return }

            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                fail("I didn't catch that.")
                return
            }

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
        engine.abort()
        speaker.stop()
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

        let request = WriteRequest(
            instruction: instruction,
            app: context,
            screenshotJPEG: screenshot,
            skills: appState.skills.skills(for: context)
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
                complete(with: result, speak: false)
                return
            }

            let result = try await client.write(request)
            guard token == runToken else { return }
            appState.phase = .writing
            appState.pill?.update()
            try? await Task.sleep(nanoseconds: 150_000_000)
            complete(with: result, speak: appState.settings.voiceReply)
        } catch {
            guard token == runToken else { return }
            fail(error.localizedDescription)
        }
    }

    // MARK: - Completion

    private func speakNow(_ sentence: String) {
        speaker.rate = Float(appState.settings.speechRate)
        speaker.voiceIdentifier = appState.settings.voiceIdentifier.isEmpty
            ? nil : appState.settings.voiceIdentifier
        speaker.speakSentence(sentence)
    }

    private func complete(with text: String, speak: Bool) {
        appState.lastResult = text
        TextInserter.insert(text)
        if speak && appState.settings.voiceReply {
            speakNow(text)
        }
        appState.phase = .done
        if appState.settings.playSounds { Sounds.done() }
        appState.pill?.update()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.appState.phase == .done else { return }
            self.appState.phase = .idle
            self.appState.pill?.hide()
        }
    }

    private func fail(_ message: String) {
        engine.abort()
        appState.phase = .error(message)
        if appState.settings.playSounds { Sounds.error() }
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
