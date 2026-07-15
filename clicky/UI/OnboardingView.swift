import AppKit
import SwiftUI

/// First-run walkthrough: what clicky is + grant the permissions.
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(Color(red: 0.4, green: 0.8, blue: 1.0))
                Text("meet clicky")
                    .font(.system(size: 26, weight: .black))
                Text("an ai buddy that lives on your mac.\nit sees your screen and listens when you talk.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 14) {
                Step(number: 1,
                     title: "hold \(appState.settings.dictateTrigger.symbol) to dictate",
                     detail: "fast, on-device speech-to-text anywhere.")
                Step(number: 2,
                     title: "hold \(appState.settings.agentTrigger.symbol) to write with your screen",
                     detail: "clicky reads your screen and writes the reply, prompt, or note for you.")
                Step(number: 3,
                     title: "grant permissions",
                     detail: "microphone, screen recording, and accessibility.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))

            VStack(spacing: 8) {
                Button("Open Permission Settings") {
                    Permissions.accessibilityAuthorized(prompt: true)
                    Permissions.openScreenRecordingSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("I'm set up — let's go") {
                    appState.finishOnboarding()
                }
            }

            Text("made by farza <3 · reimagined as clicky")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct Step: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.2)))
                .foregroundStyle(Color(red: 0.2, green: 0.6, blue: 0.9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingView().environmentObject(AppState())
}
