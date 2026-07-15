import AppKit
import SwiftUI

/// Preferences: API key, triggers, language, skills.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            SkillsSettings()
                .tabItem { Label("Skills", systemImage: "sparkles") }
            PermissionsSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .environmentObject(appState)
        .padding(20)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""

    var body: some View {
        Form {
            Section("Model") {
                SecureField("OpenAI API key", text: $apiKey)
                    .onAppear { apiKey = appState.settings.apiKey }
                    .onChange(of: apiKey) { _, newValue in
                        appState.settings.apiKey = newValue
                    }
                TextField("Model", text: Binding(
                    get: { appState.settings.model },
                    set: { appState.settings.model = $0 }
                ))
                Text("Used only for screen-aware writing. Dictation runs on-device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Triggers") {
                Picker("Dictate (raw text)", selection: Binding(
                    get: { appState.settings.dictateTrigger },
                    set: { appState.settings.dictateTrigger = $0 }
                )) {
                    ForEach(TriggerKey.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Write with screen", selection: Binding(
                    get: { appState.settings.agentTrigger },
                    set: { appState.settings.agentTrigger = $0 }
                )) {
                    ForEach(TriggerKey.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Hold to talk, release to run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Send a screenshot as context", isOn: Binding(
                    get: { appState.settings.includeScreenshot },
                    set: { appState.settings.includeScreenshot = $0 }
                ))
                Toggle("Play sounds", isOn: Binding(
                    get: { appState.settings.playSounds },
                    set: { appState.settings.playSounds = $0 }
                ))
                TextField("Language", text: Binding(
                    get: { appState.settings.localeIdentifier },
                    set: { appState.settings.localeIdentifier = $0 }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

private struct SkillsSettings: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skills are markdown files that steer clicky for a task.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(appState.skills.skills) { skill in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(skill.name).fontWeight(.medium)
                            if !skill.appMatch.isEmpty {
                                Text(skill.appMatch.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { skill.enabled },
                            set: { appState.skills.setEnabled($0, for: skill) }
                        ))
                        .labelsHidden()
                    }
                }
            }

            HStack {
                Button("Open Skills Folder") {
                    NSWorkspace.shared.open(appState.skills.directoryURL)
                }
                Button("Reload") { appState.skills.reload() }
                Spacer()
            }
        }
    }
}

private struct PermissionsSettings: View {
    var body: some View {
        Form {
            Section("clicky needs a few permissions") {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Global hotkeys + pasting the result.",
                    action: Permissions.openAccessibilitySettings
                )
                PermissionRow(
                    title: "Screen Recording",
                    detail: "See your screen for context.",
                    action: Permissions.openScreenRecordingSettings
                )
                PermissionRow(
                    title: "Microphone",
                    detail: "Hear what you say.",
                    action: Permissions.openMicrophoneSettings
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings", action: action)
        }
    }
}
