# Stealth + Memory — discreet UI, local-only recall

## Stealth (Settings → Stealth)

Discreet, not covert. macOS **always** shows mic / screen-recording
indicators while listening or capturing — stealth cannot hide those.

- **Stealth mode:** tiny `circle` menu icon when idle, minimal pill
  (dot + `…`), sounds auto-muted via `soundsAllowed`.
- **Boss-key:** `Cmd+Shift+H` cancels the run and hides the pill
  (`stealthHidden`). Any new hold brings clicky back.
- **Menu:** status collapses to `ready` / `…` / `error` — never leaks
  transcript or wake phrase.

Files: `clicky/Core/Settings.swift` (stealth prefs + `soundsAllowed`),
`clicky/Core/AppState.swift` (`stealthHidden`, `menuBarSymbol`),
`clicky/App/AppDelegate.swift` (boss-key monitor),
`clicky/UI/PillController.swift` + `PillView.swift` (minimal/hidden),
`clicky/UI/MenuBarContent.swift` (generic status).

## Memory (Settings → Memory)

Per-user, local-only (`UserDefaults` + markdown files). Nothing syncs.

- Store: `~/Library/Application Support/clicky/Memory/YYYY-MM-DD.md`
  (`clicky/Core/MemoryStore.swift`). Custom folder override in Settings.
- Point the folder at `~/Obsidian Vault/Clicky` and Obsidian browses the
  same files — no import step.
- Recall: keyword-overlap over last 14 days, top hits injected into the
  system prompt (`LLMClient.swift:WriteRequest.memories`). No embeddings.
- Remember: every agent turn appends instruction + clipped output.
  Dictate mode never writes (avoids noise).
- Future Claude Mem / MCP sidecar only needs to implement
  `recall(for:)` + `remember(instruction:output:app:)`.

## Test (Mac)

1. `open clicky.xcodeproj`, signing team, `⌘R`.
2. Stealth on → idle icon = dot, run = pill mini, sounds silent.
3. `Cmd+Shift+H` mid-run → cancelled + hidden; hold `fn` → back.
4. Memory on → agent run → `Open Folder` shows today's `.md`.
5. Set folder to Obsidian subfolder → same file appears in Obsidian.
6. Restart app → follow-up references past turn (recall works).
