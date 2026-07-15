# clicky

**an ai buddy that lives on your mac.**

clicky is a native macOS **screen-aware dictation** app. Hold a key and talk —
it transcribes your voice on-device in real time. Hold a different key and it
*reads your screen* and writes the actual text for you: a reply in Gmail, a
prompt in Claude Code, a note in Notes — in your own voice.

This is an open clone of [heyclicky.com](https://heyclicky.com) (made by farza),
rebuilt from scratch in Swift/SwiftUI.

https://github.com/dabit3/clicky

---

## How it works

clicky lives in your menu bar (no Dock icon). It's **push-to-talk**:

| Hold | Mode | What happens |
| --- | --- | --- |
| **Globe/fn** (default) | Dictate | Fast, on-device speech-to-text. The transcript is pasted where your cursor is. |
| **Option ⌥** (default) | Write with screen | clicky captures your screen + the frontmost app, sends it with your spoken instruction to a vision model, and pastes the finished text. |

A floating **pill** appears next to your cursor showing the active app, a live
waveform while you speak, and the status as it thinks and writes. Press **Esc**
to cancel.

### Pipeline

```
hold key ─▶ AVAudioEngine tap ─┬─▶ SFSpeechRecognizer (on-device)  ─▶ transcript
                               └─▶ RMS levels ─▶ waveform pill

release ─▶ dictate mode: paste transcript
       └─▶ agent mode:
             ScreenCaptureKit screenshot + frontmost app + enabled skills
                 ─▶ OpenAI (gpt-4o, vision) ─▶ text ─▶ paste (⌘V)
```

## Skills

"Skills" are markdown files that steer clicky for a task (reply to email in your
voice, write a Claude Code prompt, YC founder advice, …). They live in:

```
~/Library/Application Support/clicky/Skills/*.md
```

Each file has simple frontmatter — `name:` and an optional `apps:` list that
scopes the skill to matching apps:

```markdown
---
name: Gmail Reply
apps: [gmail, mail, chrome]
---
When replying to an email, write in the user's warm, concise first-person voice…
```

clicky seeds a few defaults on first launch. Toggle them in **Settings → Skills**.

## Build & run

Requirements: **macOS 14+** and **Xcode 16+**.

```bash
git clone https://github.com/dabit3/clicky.git
cd clicky
open clicky.xcodeproj
```

1. Select the **clicky** scheme and your team under *Signing & Capabilities*
   (Automatic signing; the app runs unsandboxed with Hardened Runtime).
2. Press **⌘R**.
3. Grant permissions when prompted (or in **Settings → Permissions**):
   - **Microphone** & **Speech Recognition** — to hear and transcribe you.
   - **Accessibility** — for the global hotkeys and pasting.
   - **Screen Recording** — for screen-aware writing.
4. Add your **OpenAI API key** in **Settings → General** to enable screen-aware
   writing. (Plain dictation works with no key — it's fully on-device. Without a
   key, agent mode falls back to a harmless demo response.)

## Project layout

```
clicky/
├── App/            App entry + AppDelegate (menu bar, wiring)
├── Core/
│   ├── HotkeyManager        global push-to-talk modifiers
│   ├── DictationEngine      mic capture, Speech, live levels
│   ├── DictationController   orchestrates a dictation run
│   ├── ScreenContextProvider ScreenCaptureKit screenshot
│   ├── FrontmostAppObserver  what app you're in
│   ├── LLMClient            OpenAI vision call
│   ├── TextInserter         pasteboard + ⌘V
│   ├── SkillStore           markdown skills
│   ├── Settings / Keychain / Permissions
│   └── AppState             shared observable state
└── UI/             PillView/PillController, WaveformView, Settings, Onboarding, MenuBar
```

## Notes

- **Privacy:** dictation uses Apple's on-device recognizer. Only *agent mode*
  sends a screenshot + your instruction to OpenAI, and only when you've set a key.
- The API key is stored in the macOS **Keychain**, never on disk in plaintext.
- clicky runs outside the App Sandbox because global hotkeys, screen capture, and
  pasting into other apps require it; Hardened Runtime stays on.

---

Original concept & design: **farza** — https://heyclicky.com
This repository is an independent, educational reimplementation.
