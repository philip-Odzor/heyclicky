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
    func stop() async -> String {
        guard isRunning else { return transcript }
        isRunning = false
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
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognition isn't available for this language."
        case .emptyTranscript: return "I didn't catch that."
        }
    }
}
