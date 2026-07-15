import AppKit

/// Snapshot of the app that was frontmost when dictation started.
struct FrontmostApp {
    let name: String
    let bundleID: String
    let icon: NSImage?

    static let unknown = FrontmostApp(name: "your screen", bundleID: "", icon: nil)
}

/// Reads the frontmost application so the pill can show context and the model
/// can tailor its output (e.g. "in Gmail, reply in your voice").
enum FrontmostAppObserver {
    static func current() -> FrontmostApp {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        return FrontmostApp(
            name: app.localizedName ?? "your screen",
            bundleID: app.bundleIdentifier ?? "",
            icon: app.icon
        )
    }
}
