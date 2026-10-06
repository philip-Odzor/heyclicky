import AppKit
import Combine
import SwiftUI

/// Owns the app-wide singletons and wires the hotkeys to the dictation flow.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var hotkeyManager: HotkeyManager?
    private var pill: PillController?
    private var wakeListener: WakeWordListener?
    private var bossMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar accessory app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        let pill = PillController(appState: appState)
        self.pill = pill
        appState.pill = pill

        let hotkeys = HotkeyManager(settings: appState.settings)
        hotkeys.onEvent = { [weak self] event in
            self?.handle(event)
        }
        hotkeys.start()
        self.hotkeyManager = hotkeys
        appState.hotkeyManager = hotkeys

        // Ask for the permissions we can request up front. Screen recording and
        // accessibility are surfaced lazily the first time they're needed.
        Task { await appState.controller.prepare() }

        // Wake word (opt-in): re-apply whenever the phase settles or the
        // user flips the toggle in Settings.
        let listener = WakeWordListener()
        listener.onWake = { [weak self] in
            Task { @MainActor in
                self?.appState.controller.beginHandsFree()
            }
        }
        self.wakeListener = listener
        appState.$phase
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyWakePolicy()
                }
            }
            .store(in: &cancellables)
        // objectWillChange fires before the new value lands; defer a beat.
        appState.settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self?.applyWakePolicy()
                }
            }
            .store(in: &cancellables)
        applyWakePolicy()

        // Boss-key (opt-in): Cmd+Shift+H cancels any run and hides the pill.
        // The next begin() clears stealthHidden so clicky comes back.
        bossMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                guard self.appState.settings.bossKeyEnabled else { return }
                if event.modifierFlags.contains(.command),
                   event.modifierFlags.contains(.shift),
                   event.charactersIgnoringModifiers?.lowercased() == "h" {
                    self.appState.controller.cancel()
                    self.appState.stealthHidden = true
                    self.appState.pill?.hide()
                }
            }
        }

        if appState.settings.showOnboarding {
            appState.presentOnboarding()
        }
    }

    /// The wake listener only holds the mic while clicky is otherwise idle:
    /// never during a listen, a model run, or speech. Toggle lives in
    /// Settings → Voice and applies immediately.
    private func applyWakePolicy() {
        guard let listener = wakeListener else { return }
        let settings = appState.settings
        guard settings.wakeEnabled else {
            if listener.isListening { listener.stop() }
            if appState.wakeListening { appState.wakeListening = false }
            return
        }
        switch appState.phase {
        case .idle, .done, .error:
            let phrase = settings.wakePhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else {
                listener.stop()
                appState.wakeListening = false
                return
            }
            if !listener.isListening {
                listener.start(phrases: [phrase])
            } else {
                listener.refresh(phrase: phrase)
            }
            if !appState.wakeListening { appState.wakeListening = true }
        case .listening, .thinking, .writing:
            if listener.isListening { listener.stop() }
            if appState.wakeListening { appState.wakeListening = false }
        }
    }

    private func handle(_ event: HotkeyManager.Event) {
        switch event {
        case .pressed(let mode):
            appState.controller.begin(mode: mode)
        case .released:
            appState.controller.finish()
        case .cancelled:
            appState.controller.cancel()
        }
    }
}
