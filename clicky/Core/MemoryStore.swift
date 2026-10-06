import Foundation

/// Always-remember, per-user local-only. No sync, no server, no embeddings.
///
/// Storage: markdown daily logs in Application Support `clicky/Memory`.
/// Point Settings → Memory folder at an Obsidian vault subfolder
/// (e.g. `~/Obsidian Vault/Clicky`) and the same files become browable
/// graph nodes there — zero extra code, user gets search free.
///
/// Recall is keyword-overlap over recent files ($0, offline). A future
/// Claude Mem / MCP sidecar can implement the same two methods.
@MainActor
final class MemoryStore: ObservableObject {
    @Published private(set) var entryCount: Int = 0

    private let fileManager = FileManager.default

    /// Resolved folder: custom path from Settings, else app default.
    /// Shared UserDefaults key with Settings.memoryFolder (no coupling).
    var directory: URL {
        let custom = (UserDefaults.standard.string(forKey: "memoryFolder") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("clicky/Memory", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var directoryURL: URL { directory }

    init() {
        refreshCount()
    }

    func refreshCount() {
        let files = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        entryCount = files.filter { $0.hasSuffix(".md") }.count
    }

    /// Top relevant snippets for an instruction (max ~8000 chars).
    /// Enabled check lives with the caller so this stays testable.
    func recall(for query: String, maxChars: Int = 8000) -> [String] {
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
        guard !words.isEmpty else { return recentTail(maxChars: 2000) }
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        let md = files.filter { $0.pathExtension == "md" }
            .sorted { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            .prefix(14)
        var hits: [(score: Int, text: String)] = []
        for url in md {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for chunk in raw.components(separatedBy: "\n\n") {
                let low = chunk.lowercased()
                var score = 0
                for w in words where low.contains(w) { score += 1 }
                if score > 0 {
                    hits.append((score, chunk.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }
        let sorted = hits.sorted { $0.score > $1.score }.map(\.text)
        var out: [String] = []
        var used = 0
        for h in sorted {
            guard used + h.count < maxChars else { break }
            out.append(h)
            used += h.count
        }
        return out.isEmpty ? recentTail(maxChars: 2000) : out
    }

    /// Append one turn to today's log. Truncates output to keep files small.
    func remember(instruction: String, output: String, app: String) {
        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanInstruction.isEmpty else { return }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: Date())
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: Date())
        let clipped = trimmed.count > 2000 ? String(trimmed.prefix(2000)) + "…" : trimmed
        let entry = "## \(time) — \(app)\n**You said:** \(cleanInstruction)\n**Clicky wrote:** \(clipped)\n\n"
        let url = directory.appendingPathComponent("\(day).md")
        if fileManager.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: entry.data(using: .utf8)!)
                try? handle.close()
            }
        } else {
            try? "# Clicky memory — \(day)\n\n\(entry)".write(to: url, atomically: true, encoding: .utf8)
        }
        refreshCount()
    }

    private func recentTail(maxChars: Int) -> [String] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        guard let latest = files.filter({ $0.pathExtension == "md" }).sorted(by: {
            let da = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }).first,
              let raw = try? String(contentsOf: latest, encoding: .utf8) else { return [] }
        let tail = String(raw.suffix(maxChars))
        return tail.isEmpty ? [] : [tail]
    }
}
