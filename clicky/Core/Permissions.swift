import AppKit
import ApplicationServices
import AVFoundation
import Speech

/// Convenience checks + prompts for the four permissions clicky needs.
enum Permissions {
    static var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var speechAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Accessibility is required for global hotkeys and pasting.
    @discardableResult
    static func accessibilityAuthorized(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        open("com.apple.preference.security?Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        open("com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openMicrophoneSettings() {
        open("com.apple.preference.security?Privacy_Microphone")
    }

    private static func open(_ path: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(path)") else { return }
        NSWorkspace.shared.open(url)
    }
}
