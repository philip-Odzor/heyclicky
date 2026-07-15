import AppKit
import SwiftUI

/// Owns the app-wide singletons and wires the hotkeys to the dictation flow.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var hotkeyManager: HotkeyManager?
    private var pill: PillController?

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

        if appState.settings.showOnboarding {
            appState.presentOnboarding()
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
