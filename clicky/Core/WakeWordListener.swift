import AppKit

/// Hands-free activation: listens for a spoken name ("hey clicky",
/// "jarvis", …) and fires `onWake`.
///
/// Phase A and B share this class. It uses the built-in command-based
/// speech recognizer (`NSSpeechRecognizer`), which is Apple's sanctioned
/// always-on path: low power, no custom audio plumbing, no ML model to
/// ship. Custom phrases work because commands are arbitrary strings —
/// Phase B is the same code with the user's phrase.
///
/// Opt-in only: while listening the system shows the mic indicator.
/// The owner (AppDelegate) stops the listener whenever the mic belongs to
/// a dictation run, so the two never capture at once.
final class WakeWordListener: NSObject {
    var onWake: (() -> Void)?

    private var recognizer: NSSpeechRecognizer?
    private(set) var isListening = false
    private var phrases: [String] = []

    /// Start listening for any of `phrases`. Restarts cleanly if already on.
    func start(phrases: [String]) {
        let cleaned = phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            stop()
            return
        }
        // Case-insensitive matching: register both casings.
        var commands: [String] = []
        for p in cleaned {
            commands.append(p)
            let lower = p.lowercased()
            if lower != p { commands.append(lower) }
        }
        stop()
        let r = NSSpeechRecognizer()
        r.commands = commands
        r.delegate = self
        r.startListening()
        recognizer = r
        self.phrases = cleaned
        isListening = true
    }

    func stop() {
        recognizer?.stopListening()
        recognizer = nil
        isListening = false
    }

    /// Restart with the latest phrase if currently listening.
    func refresh(phrase: String) {
        guard isListening else { return }
        start(phrases: [phrase])
    }
}

extension WakeWordListener: NSSpeechRecognizerDelegate {
    func speechRecognizer(_ sender: NSSpeechRecognizer, didRecognizeCommand command: String) {
        onWake?()
    }
}
