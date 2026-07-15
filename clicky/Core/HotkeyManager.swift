import AppKit
import Carbon.HIToolbox

/// Listens for global push-to-talk modifier keys.
///
/// clicky is push-to-talk: hold the dictation key for raw speech-to-text, hold
/// the agent key for screen-aware writing, and release to run. Watching global
/// modifier changes requires Accessibility permission.
final class HotkeyManager {
    enum Event {
        case pressed(DictationMode)
        case released
        case cancelled
    }

    var onEvent: ((Event) -> Void)?

    private let settings: Settings
    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var activeMode: DictationMode?

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        // Global monitors observe events destined for other apps; requires the
        // app to be trusted for Accessibility.
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }
        // Also observe locally so the shortcut works when a clicky window is key.
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }
        // Escape cancels an in-flight dictation.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) { self?.cancel() }
        }
    }

    func stop() {
        [flagsMonitor, keyMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        flagsMonitor = nil
        keyMonitor = nil
    }

    private func cancel() {
        guard activeMode != nil else { return }
        activeMode = nil
        onEvent?(.cancelled)
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags
        let dictateDown = isDown(settings.dictateTrigger, in: flags)
        let agentDown = isDown(settings.agentTrigger, in: flags)

        if let mode = activeMode {
            // Currently recording — release when the trigger for that mode lifts.
            let stillDown = (mode == .dictate && dictateDown) || (mode == .agent && agentDown)
            if !stillDown {
                activeMode = nil
                onEvent?(.released)
            }
            return
        }

        // Nothing active yet: agent takes precedence if both happen to be down.
        if agentDown {
            activeMode = .agent
            onEvent?(.pressed(.agent))
        } else if dictateDown {
            activeMode = .dictate
            onEvent?(.pressed(.dictate))
        }
    }

    private func isDown(_ key: TriggerKey, in flags: NSEvent.ModifierFlags) -> Bool {
        switch key {
        case .option: return flags.contains(.option)
        case .control: return flags.contains(.control)
        case .command: return flags.contains(.command)
        case .function: return flags.contains(.function)
        }
    }
}
