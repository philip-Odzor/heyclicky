import AVFoundation
import Speech

/// Captures microphone audio, streams it into Apple's on-device speech
/// recognizer, and publishes both the live transcript and normalized audio
/// levels for the waveform.
@MainActor
final class DictationEngine: ObservableObject {
    @Published private(set) var transcript: String = ""
    @Published private(set) var level: Float = 0

    var onLevel: ((Float) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false

    // MARK: - Alternate STT engines (Groq Whisper / local command)

    /// Set by the controller before start(). .apple keeps the on-device path.
    var sttEngine: STTEngine = .apple
    var groqAPIKey: String = ""
    var groqModel: String = "whisper-large-v3-turbo"
    var groqLanguage: String = ""
    var localSTTCommand: String = ""
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    func updateLocale(_ identifier: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
    }

    /// Requests microphone + speech-recognition authorization.
    func requestAuthorization() async -> Bool {
        let mic = await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { cont.resume(returning: $0) }
        }
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        return mic && speech
    }

    func start() throws {
        guard !isRunning else { return }
        transcript = ""

        // File path: record raw mic audio, transcribe on stop.
        if sttEngine != .apple {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("clicky-stt-\(UUID().uuidString).wav")
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            do {
                audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
            } catch {
                throw DictationError.recordingFailed
            }
            recordingURL = url
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                try? self?.audioFile?.write(buffer)
                let level = Self.rms(buffer)
                Task { @MainActor in
                    self?.level = level
                    self?.onLevel?(level)
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRunning = true
            return
        }

        if recognizer == nil {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        guard let recognizer, recognizer.isAvailable else {
            throw DictationError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            let level = Self.rms(buffer)
            Task { @MainActor in
                self?.level = level
                self?.onLevel?(level)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in self.transcript = text }
        }
    }

    /// Stops capture and returns the best available transcript.
    /// Throws for the file engines when recording or transcription fails.
    func stop() async throws -> String {
        guard isRunning else { return transcript }
        isRunning = false

        // File path: finalize the WAV, transcribe it, clean up.
        if sttEngine != .apple {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            audioFile = nil
            level = 0
            guard let url = recordingURL else { return transcript }
            recordingURL = nil
            defer { try? FileManager.default.removeItem(at: url) }
            switch sttEngine {
            case .apple:
                return transcript
            case .groqWhisper:
                let text = try await VoiceProviders.groqTranscribe(
                    audioURL: url,
                    apiKey: groqAPIKey,
                    model: groqModel,
                    language: groqLanguage
                )
                transcript = text
                return text
            case .localCommand:
                let text = try await VoiceProviders.localTranscribe(
                    commandTemplate: localSTTCommand,
                    audioURL: url
                )
                transcript = text
                return text
            }
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request?.endAudio()

        // Give the recognizer a brief moment to emit its final result.
        try? await Task.sleep(nanoseconds: 250_000_000)

        task?.finish()
        task = nil
        request = nil
        level = 0
        return transcript
    }

    func abort() {
        guard isRunning else { return }
        isRunning = false
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        audioFile = nil
        if let url = recordingURL {
            recordingURL = nil
            try? FileManager.default.removeItem(at: url)
        }
        transcript = ""
        level = 0
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(count))
        // Map to a pleasant 0...1 range for the waveform.
        let scaled = min(1, max(0, (rms * 12)))
        return scaled
    }
}

enum DictationError: LocalizedError {
    case recognizerUnavailable
    case recordingFailed
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognition isn't available for this language."
        case .recordingFailed: return "Couldn't start the microphone recording."
        case .emptyTranscript: return "I didn't catch that."
        }
    }
}
