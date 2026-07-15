import SwiftUI

/// Entry point for clicky — a screen-aware dictation "buddy" that lives in your
/// menu bar. The heavy lifting (global hotkeys, the floating pill, dictation)
/// is driven by ``AppDelegate`` so it keeps working no matter which window,
/// if any, is on screen.
@main
struct ClickyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appDelegate.appState)
        } label: {
            Image(systemName: appDelegate.appState.menuBarSymbol)
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
                .frame(width: 620, height: 460)
        }
    }
}
