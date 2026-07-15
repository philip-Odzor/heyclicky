import Foundation

/// A markdown "skill" — a reusable knowledge pack that steers clicky's writing
/// for a particular task (e.g. "reply to Gmail in my voice"). Stored as `.md`
/// files in Application Support so users can add their own.
struct Skill: Identifiable, Equatable {
    let id: String       // file name without extension
    var name: String
    var body: String
    var appMatch: [String]   // bundle-id fragments this skill applies to; empty = global
    var enabled: Bool
}

/// Loads, seeds, and persists skills on disk.
@MainActor
final class SkillStore: ObservableObject {
    @Published private(set) var skills: [Skill] = []

    private let fileManager = FileManager.default

    private var directory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("clicky/Skills", isDirectory: true)
    }

    init() {
        seedIfNeeded()
        reload()
    }

    var directoryURL: URL { directory }

    func reload() {
        let disabled = disabledIDs()
        var loaded: [Skill] = []
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { skills = []; return }

        for url in files where url.pathExtension == "md" {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let parsed = Self.parse(raw)
            let id = url.deletingPathExtension().lastPathComponent
            loaded.append(Skill(
                id: id,
                name: parsed.name ?? id,
                body: parsed.body,
                appMatch: parsed.appMatch,
                enabled: !disabled.contains(id)
            ))
        }
        skills = loaded.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// The skills that apply to the current app: global ones plus any whose
    /// `apps:` frontmatter matches the frontmost bundle id.
    func skills(for app: FrontmostApp) -> [Skill] {
        skills.filter { skill in
            guard skill.enabled else { return false }
            if skill.appMatch.isEmpty { return true }
            let bundle = app.bundleID.lowercased()
            let name = app.name.lowercased()
            return skill.appMatch.contains { fragment in
                let f = fragment.lowercased()
                return bundle.contains(f) || name.contains(f)
            }
        }
    }

    func setEnabled(_ enabled: Bool, for skill: Skill) {
        var disabled = disabledIDs()
        if enabled { disabled.remove(skill.id) } else { disabled.insert(skill.id) }
        UserDefaults.standard.set(Array(disabled), forKey: Self.disabledKey)
        reload()
    }

    private func disabledIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.disabledKey) ?? [])
    }

    private static let disabledKey = "skills.disabled"

    // MARK: - Seeding

    private func seedIfNeeded() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let existing = try? fileManager.contentsOfDirectory(atPath: directory.path),
              existing.filter({ $0.hasSuffix(".md") }).isEmpty else { return }

        for (name, content) in Self.defaultSkills {
            let url = directory.appendingPathComponent(name)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Parsing

    private static func parse(_ raw: String) -> (name: String?, appMatch: [String], body: String) {
        guard raw.hasPrefix("---") else { return (nil, [], raw) }
        let parts = raw.components(separatedBy: "---")
        guard parts.count >= 3 else { return (nil, [], raw) }
        let front = parts[1]
        let body = parts[2...].joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)

        var name: String?
        var apps: [String] = []
        for line in front.split(separator: "\n") {
            let pair = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard pair.count == 2 else { continue }
            switch pair[0].lowercased() {
            case "name": name = pair[1]
            case "apps":
                apps = pair[1]
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            default: break
            }
        }
        return (name, apps, body)
    }

    private static let defaultSkills: [(String, String)] = [
        ("Gmail Reply.md", """
        ---
        name: Gmail Reply
        apps: [gmail, mail, chrome, safari]
        ---
        When replying to an email, write in the user's warm, concise first-person
        voice. Open with a friendly line, answer everything the sender asked, and
        close with a clear next step. Keep it under ~120 words unless the thread
        is clearly formal. Never invent facts that aren't on screen.
        """),
        ("Claude Code Prompt.md", """
        ---
        name: Claude Code Prompt
        apps: [terminal, iterm, ghostty, code, cursor]
        ---
        Turn the spoken idea into a precise engineering prompt for a coding agent.
        Reference the files, errors, or UI visible on screen. Be specific about the
        desired outcome and constraints. Output the prompt only — no backticks.
        """),
        ("YCombinator.md", """
        ---
        name: Y Combinator
        apps: []
        ---
        YC partner brain: business models, pricing, landing pages, and blunt
        founder advice in the style of a YC group partner. When asked about
        startups, be direct, concrete, and default to action.
        """)
    ]
}
