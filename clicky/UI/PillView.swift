import AppKit
import SwiftUI

/// The floating "clicky" pill that appears near the cursor while dictating.
/// Mirrors the app in the demo: app-context chip, a status line, and a live
/// waveform / spinner depending on the phase.
struct PillView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        // Boss-key: render nothing (panel stays hidden by controller too).
        if appState.stealthHidden {
            EmptyView()
        } else if appState.settings.stealthEnabled && appState.settings.minimalPill {
            minimalBody
        } else {
            fullBody
        }
    }

    /// Discreet pill: small dot + short status, no app chip, no shadow.
    private var minimalBody: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
            Text(shortStatus)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.82))
        )
        .foregroundStyle(.white)
    }

    private var shortStatus: String {
        switch appState.phase {
        case .idle: return "ready"
        case .listening: return "…"
        case .thinking, .writing: return "…"
        case .done: return "done"
        case .error: return "error"
        }
    }

    private var fullBody: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                contextChip
                statusLine
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        )
        .foregroundStyle(.white)
    }

    @ViewBuilder private var leading: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 30, height: 30)
            switch appState.phase {
            case .thinking, .writing:
                Image(systemName: "sparkles").font(.system(size: 13, weight: .bold))
            case .error:
                Image(systemName: "exclamationmark").font(.system(size: 13, weight: .bold))
            case .done:
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
            default:
                Circle().fill(accent).frame(width: 9, height: 9)
            }
        }
        .foregroundStyle(accent)
    }

    @ViewBuilder private var contextChip: some View {
        HStack(spacing: 5) {
            if let icon = appState.contextAppIcon {
                Image(nsImage: icon).resizable().frame(width: 13, height: 13)
            }
            Text(appState.contextAppName.isEmpty ? "clicky" : appState.contextAppName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    @ViewBuilder private var statusLine: some View {
        Text(statusText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
    }

    @ViewBuilder private var trailing: some View {
        switch appState.phase {
        case .listening:
            WaveformView(levels: appState.levels, color: accent, barWidth: 2.5, spacing: 2)
                .frame(width: 84, height: 26)
        case .thinking, .writing:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        default:
            EmptyView()
        }
    }

    private var statusText: String {
        switch appState.phase {
        case .idle: return "ready"
        case .listening:
            let t = appState.transcript
            return t.isEmpty ? "listening…" : t
        case .thinking: return "thinking…"
        case .writing: return "writing…"
        case .done: return "done"
        case .error(let message): return message
        }
    }

    private var accent: Color {
        if case .error = appState.phase { return .orange }
        return Color(red: 0.4, green: 0.8, blue: 1.0)
    }
}

#Preview {
    let state = AppState()
    state.phase = .listening
    state.contextAppName = "Gmail"
    state.levels = (0..<28).map { _ in Float.random(in: 0.1...1) }
    return PillView().environmentObject(state).padding(40)
}
