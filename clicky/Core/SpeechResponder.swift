import AVFoundation

/// Free on-device speech output. No ElevenLabs, no network, no API key.
/// Used for agent-mode replies so clicky talks back in realtime.
final class SpeechResponder: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false

    /// AVSpeechUtterance rate 0.0...1.0. 0.5 is the natural default.
    var rate: Float = 0.5
    /// Optional AVSpeechSynthesisVoice identifier. nil = system default.
    var voiceIdentifier: String?

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Speak full text, split into sentences for natural pauses.
    /// Calling speak while speaking queues behind the current reply.
    /// Call `stop()` first for barge-in (interrupt).
    func speak(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        for sentence in Self.sentences(from: cleaned) {
            speakSentence(sentence)
        }
    }

    /// Speak one streaming chunk immediately. Used while LLM tokens arrive
    /// so voice overlaps generation (simulated realtime, ~1s to first word).
    func speakSentence(_ sentence: String) {
        let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = rate
        if let id = voiceIdentifier, !id.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }
        isSpeaking = true
        synth.speak(utterance)
    }

    /// Interrupt immediately. Called on new hold (barge-in) and cancel.
    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - Sentence splitting (shared with streaming LLM path)

    static func sentences(from text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == "\n" {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out.append(t) }
                current = ""
            } else if ch == "." || ch == "!" || ch == "?" {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                // Avoid splitting tiny fragments ("e.g.", "v1.2") mid-stream.
                if t.count >= 20 {
                    out.append(t)
                    current = ""
                }
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }
}

extension SpeechResponder: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = synthesizer.isSpeaking
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = synthesizer.isSpeaking
    }
}
