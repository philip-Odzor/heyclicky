import AppKit
import SwiftUI

/// The dropdown shown from the menu-bar icon.
struct MenuBarContent: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            Text("clicky")
                .font(.headline)

            Text(statusSummary)
                .foregroundStyle(.secondary)

            Divider()

            Text("hold \(appState.settings.dictateTrigger.symbol) to dictate")
            Text("hold \(appState.settings.agentTrigger.symbol) to write with your screen")
            if appState.settings.wakeEnabled {
                Text("or say “\(appState.settings.wakePhrase)”")
            }

            Divider()

            if !appState.settings.hasAPIKey {
                Button("Add model key for screen-aware writing…") { openSettings() }
            }

            Button("Settings…") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)

            Button("Permissions & Help…") { appState.presentOnboarding() }

            Divider()

            Button("Quit clicky") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var statusSummary: String {
        if appState.wakeListening {
            return "wake word on — say “\(appState.settings.wakePhrase)”"
        }
        switch appState.phase {
        case .idle, .done: return "ready — \(appState.skills.skills.filter(\.enabled).count) skills on"
        case .listening: return "listening…"
        case .thinking: return "thinking…"
        case .writing: return "writing…"
        case .error(let message): return message
        }
    }
}
