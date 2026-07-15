import AppKit
import Combine
import SwiftUI

/// Where clicky currently is in the dictation lifecycle.
enum DictationPhase: Equatable {
    case idle
    case listening
    case thinking
    case writing
    case done
    case error(String)
}

/// How the current dictation should be interpreted.
enum DictationMode: Equatable {
    /// Raw, fast speech-to-text: insert the transcript verbatim.
    case dictate
    /// Screen-aware: use the visible screen + transcript as an instruction and
    /// let the model write the actual text.
    case agent
}

/// App-wide observable state shared with the SwiftUI surfaces (menu bar, pill,
/// settings). Acts as the composition root for the various controllers.
@MainActor
final class AppState: ObservableObject {
    @Published var phase: DictationPhase = .idle
    @Published var transcript: String = ""
    /// Rolling window of normalized audio levels (0...1) for the waveform.
    @Published var levels: [Float] = Array(repeating: 0, count: 28)
    @Published var contextAppName: String = ""
    @Published var contextAppIcon: NSImage?
    @Published var lastResult: String = ""

    let settings = Settings()
    let skills = SkillStore()

    lazy var controller = DictationController(appState: self)

    weak var pill: PillController?
    weak var hotkeyManager: HotkeyManager?

    private var onboarding: NSWindow?

    var menuBarSymbol: String {
        switch phase {
        case .idle, .done: return "waveform"
        case .listening: return "waveform.circle.fill"
        case .thinking, .writing: return "sparkles"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    /// The human-readable hint shown in the pill for the active mode + context.
    func hint(for mode: DictationMode) -> String {
        switch mode {
        case .dictate:
            return "listening…"
        case .agent:
            let ctx = contextAppName.isEmpty ? "your screen" : contextAppName
            return "writing with \(ctx)"
        }
    }

    func presentOnboarding() {
        if let onboarding {
            onboarding.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: OnboardingView().environmentObject(self))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to clicky"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 460, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboarding = window
    }

    func finishOnboarding() {
        settings.showOnboarding = false
        onboarding?.close()
    }
}
