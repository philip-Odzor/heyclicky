import AVFoundation
import Foundation

/// Free voice providers behind one router. No ElevenLabs, no subscriptions:
/// Groq Whisper (free tier) and local commands for speech-to-text,
/// Edge TTS (free, no key) and Piper (local binary) for speech-out.
/// The macOS system engines stay the default: fully offline, zero setup.
enum VoiceProviders {

    // MARK: - Process helper

    struct RunResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Resolve a binary name via PATH, or accept an absolute path as-is.
    static func resolveBinary(_ nameOrPath: String) -> String? {
        let trimmed = nameOrPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") {
            return FileManager.default.isExecutableFile(atPath: trimmed) ? trimmed : nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "command -v \(trimmed)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let found = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !found.isEmpty,
              FileManager.default.isExecutableFile(atPath: found) else { return nil }
        return found
    }

    /// Run a binary with arguments and piped stdin, with a timeout.
    /// No shell is involved, so long text never needs quoting.
    static func run(
        binary: String,
        arguments: [String],
        stdin: Data? = nil,
        timeout: TimeInterval = 180
    ) async throws -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe = Pipe()
        process.standardInput = inPipe
        try process.run()
        if let stdin {
            do {
                try inPipe.fileHandleForWriting.write(contentsOf: stdin)
            } catch {
                // The process may have exited already; ignore.
            }
            try? inPipe.fileHandleForWriting.close()
        } else {
            try? inPipe.fileHandleForWriting.close()
        }
        // Timeout race: terminate the whole run if it hangs (model load, etc.).
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await Task.detached { process.waitUntilExit() }.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if process.isRunning { process.terminate() }
            }
            try await group.next()
            group.cancelAll()
        }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunResult(status: process.terminationStatus, stdout: out, stderr: err)
    }

    // MARK: - Speech-to-text

    /// Groq Whisper transcription (free tier). `audioURL` is any WAV file.
    static func groqTranscribe(
        audioURL: URL,
        apiKey: String,
        model: String,
        language: String
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw VoiceError.missingGroqKey }
        let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        let boundary = "clicky-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model.isEmpty ? "whisper-large-v3-turbo" : model)
        field("response_format", "json")
        if !language.isEmpty { field("language", language) }
        let audio = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw VoiceError.server("Groq STT failed (HTTP \(code)): \(String(data: data, encoding: .utf8) ?? "")")
        }
        struct GroqText: Decodable { let text: String }
        let decoded = try JSONDecoder().decode(GroqText.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw VoiceError.emptyTranscript }
        return text
    }

    /// Local STT command. `{audio}` in the template is replaced with the WAV
    /// path. Stdout is the transcript. Example:
    /// `whisper-cli -m ~/models/ggml-base.en.bin -f {audio} -otxt`.
    static func localTranscribe(commandTemplate: String, audioURL: URL) async throws -> String {
        let template = commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { throw VoiceError.missingLocalCommand }
        let command = template.replacingOccurrences(of: "{audio}", with: audioURL.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await Task.detached { process.waitUntilExit() }.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                if process.isRunning { process.terminate() }
            }
            try await group.next()
            group.cancelAll()
        }
        guard process.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw VoiceError.server("Local STT exited (\(process.terminationStatus)): \(err)")
        }
        let text = (String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw VoiceError.emptyTranscript }
        return text
    }
}

// MARK: - File-playing TTS (Edge + Piper share this shape)

/// Base class: synthesize text to an audio file, then play it.
/// Subclasses only implement `synthesize(text:to:)`.
class FileTTSSpeaker {
    private var player: AVAudioPlayer?

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// Subclasses write playable audio (mp3/wav) to `outputURL`.
    func synthesize(text: String, to outputURL: URL) async throws {
        fatalError("Override synthesize(text:to:)")
    }

    func speak(text: String) async throws {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clicky-tts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try await synthesize(text: cleaned, to: url)
        try await play(url: url)
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func play(url: URL) async throws {
        let p = try AVAudioPlayer(contentsOf: url)
        player = p
        p.play()
        while p.isPlaying {
            if Task.isCancelled {
                p.stop()
                player = nil
                return
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        if player === p { player = nil }
    }
}

/// Edge TTS via the `edge-tts` CLI (free, no key: `pip install edge-tts`).
/// Direct exec, no shell: long text is one argv, never quoted.
final class EdgeTTSSpeaker: FileTTSSpeaker {
    var binary = "edge-tts"
    var voice = "en-US-AriaNeural"
    /// System rate 0.3...1.0 mapped to Edge percent.
    var rate: Double = 0.5
    /// System pitch 0.5...2.0 mapped to Edge Hz offset.
    var pitch: Double = 1.0

    override func synthesize(text: String, to outputURL: URL) async throws {
        guard let bin = VoiceProviders.resolveBinary(binary) else {
            throw VoiceError.missingBinary("edge-tts not found. Install with: pip install edge-tts")
        }
        let ratePct = Int((rate - 0.5) * 100)
        let pitchHz = Int((pitch - 1.0) * 20)
        let rateArg = "\(ratePct >= 0 ? "+" : "")\(ratePct)%"
        let pitchArg = "\(pitchHz >= 0 ? "+" : "")\(pitchHz)Hz"
        let result = try await VoiceProviders.run(
            binary: bin,
            arguments: [
                "--voice", voice,
                "--rate", rateArg,
                "--pitch", pitchArg,
                "--text", text,
                "--write-media", outputURL.path,
            ],
            timeout: 180
        )
        guard result.status == 0 else {
            throw VoiceError.server("edge-tts failed: \(result.stderr)")
        }
    }
}

/// Piper via the `piper` CLI (fully local, offline).
/// Voices: https://huggingface.co/rhasspy/piper-voices — point the model
/// setting at a downloaded .onnx file.
final class PiperTTSSpeaker: FileTTSSpeaker {
    var binary = "piper"
    var modelPath = ""
    /// -1 omits --speaker (single-speaker voices).
    var speaker = -1
    /// System rate 0.3...1.0 mapped to --length-scale (inverse).
    var rate: Double = 0.5

    override func synthesize(text: String, to outputURL: URL) async throws {
        guard let bin = VoiceProviders.resolveBinary(binary) else {
            throw VoiceError.missingBinary("piper not found. Install with: pip install piper-tts")
        }
        let model = (modelPath as NSString).expandingTildeInPath
        guard !model.isEmpty, FileManager.default.fileExists(atPath: model) else {
            throw VoiceError.missingModel("Piper voice model not set. Download one from rhasspy/piper-voices and set its .onnx path in Settings → Voice.")
        }
        let lengthScale = min(4.0, max(0.25, 0.5 / max(0.1, rate)))
        var args = ["--model", model, "--output_file", outputURL.path,
                    "--length-scale", String(format: "%.2f", lengthScale)]
        if speaker >= 0 { args += ["--speaker", String(speaker)] }
        let result = try await VoiceProviders.run(
            binary: bin,
            arguments: args,
            stdin: text.data(using: .utf8),
            timeout: 180
        )
        guard result.status == 0 else {
            throw VoiceError.server("piper failed: \(result.stderr)")
        }
    }
}

// MARK: - Router: one sync API, every engine behind it

/// Serial speech queue. System speaks instantly; Edge/Piper synthesize then
/// play per sentence, so streaming voice still overlaps generation.
/// Best-effort after paste: failures are swallowed, never fail the run.
final class VoiceOutput {
    private let system = SpeechResponder()
    private let edge = EdgeTTSSpeaker()
    private let piper = PiperTTSSpeaker()

    private struct Job {
        let text: String
        let ttsEngine: TTSEngine
        let systemVoiceId: String
        let rate: Double
        let pitch: Double
        let edgeVoice: String
        let edgeBinary: String
        let piperBinary: String
        let piperModel: String
        let piperSpeaker: Int
    }

    private var pending: [Job] = []
    private var pump: Task<Void, Never>?
    /// Pump runs detached (synthesis blocks for seconds); lock guards the queue.
    private let lock = NSLock()

    /// Snapshot settings once per call so mid-reply edits can't corrupt it.
    func speak(_ text: String, settings: Settings) {
        for sentence in SpeechResponder.sentences(from: text) {
            speakSentence(sentence, settings: settings)
        }
    }

    func speakSentence(_ sentence: String, settings: Settings) {
        let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        lock.lock()
        pending.append(Job(
            text: cleaned,
            ttsEngine: settings.ttsEngine,
            systemVoiceId: settings.voiceIdentifier,
            rate: settings.speechRate,
            pitch: settings.speechPitch,
            edgeVoice: settings.edgeVoice,
            edgeBinary: settings.edgeBinary,
            piperBinary: settings.piperBinary,
            piperModel: settings.piperModel,
            piperSpeaker: settings.piperSpeaker
        ))
        let needsPump = (pump == nil)
        lock.unlock()
        if needsPump { startPump() }
    }

    func stop() {
        lock.lock()
        pump?.cancel()
        pump = nil
        pending.removeAll()
        lock.unlock()
        system.stop()
        edge.stop()
        piper.stop()
    }

    private func startPump() {
        lock.lock()
        guard pump == nil else {
            lock.unlock()
            return
        }
        pump = Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.lock.lock()
                guard !self.pending.isEmpty else {
                    self.pump = nil
                    self.lock.unlock()
                    return
                }
                let job = self.pending.removeFirst()
                self.lock.unlock()
                await self.play(job)
            }
            self.lock.lock()
            self.pump = nil
            self.lock.unlock()
        }
        lock.unlock()
    }

    private func play(_ job: Job) async {
        switch job.ttsEngine {
        case .system:
            system.rate = Float(job.rate)
            system.pitch = Float(job.pitch)
            system.voiceIdentifier = job.systemVoiceId.isEmpty ? nil : job.systemVoiceId
            system.speakSentence(job.text)
        case .edge:
            edge.binary = job.edgeBinary
            edge.voice = job.edgeVoice.isEmpty ? "en-US-AriaNeural" : job.edgeVoice
            edge.rate = job.rate
            edge.pitch = job.pitch
            try? await edge.speak(text: job.text)
        case .piper:
            piper.binary = job.piperBinary
            piper.modelPath = job.piperModel
            piper.speaker = job.piperSpeaker
            piper.rate = job.rate
            try? await piper.speak(text: job.text)
        }
    }
}

enum VoiceError: LocalizedError {
    case missingGroqKey
    case missingLocalCommand
    case missingBinary(String)
    case missingModel(String)
    case emptyTranscript
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingGroqKey: return "Add your Groq key in Settings → Voice for Groq Whisper STT."
        case .missingLocalCommand: return "Set a local STT command in Settings → Voice."
        case .missingBinary(let m): return m
        case .missingModel(let m): return m
        case .emptyTranscript: return "I didn't catch that."
        case .server(let m): return m
        }
    }
}
