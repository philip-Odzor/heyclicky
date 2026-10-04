# Free voice + free models — no subscriptions, no ElevenLabs

This fork runs $0 infra:

- **Dictation (speech-to-text):** on-device `SFSpeechRecognizer` (`clicky/Core/DictationEngine.swift`). No key, no network.
- **Replies (text-to-speech):** on-device `AVSpeechSynthesizer` (`clicky/Core/SpeechResponder.swift`). No key, no network.
- **Brain (screen-aware writing):** any OpenAI-compatible endpoint (`clicky/Core/LLMClient.swift:OpenAIClient`). Same JSON shape, different base URL.

## 1. Reuse your Hermes free keys

Hermes keeps keys in `~/.hermes/.env`. Copy the value into clicky **Settings → General → API key** and pick the matching provider:

| Hermes env var | clicky Provider | Base URL (auto) | Model example |
|---|---|---|---|
| `GROQ_API_KEY` | Groq (free tier) | `https://api.groq.com/openai/v1/chat/completions` | `meta-llama/llama-4-scout-17b-16e-instruct` |
| `GEMINI_API_KEY` | Gemini (free AI Studio key) | `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions` | `gemini-2.5-flash` |
| `OPENROUTER_API_KEY` | OpenRouter | `https://openrouter.ai/api/v1/chat/completions` | `qwen/qwen2.5-vl-72b-instruct:free` |
| `OPENAI_API_KEY` | OpenAI | `https://api.openai.com/v1/chat/completions` | `gpt-4o` |
| — (Ollama) | Ollama (local, no key) | `http://localhost:11434/v1/chat/completions` | `qwen2.5vl` (`ollama pull qwen2.5vl`) |
| — (Hermes API server) | Hermes API server (local) | `http://localhost:8000/v1/chat/completions` (edit to match yours) | `hermes-default` |

Switching provider snaps Base URL + model to sane defaults; edit them if you need a specific model.

## 2. Voice settings

- **Speak replies aloud** = on for realtime conversation (agent mode only; dictate mode never echoes).
- **Speak as it generates** = on for ~1s to first word (streams sentences while tokens arrive). Off = speak once at the end.
- **Rate** slider = `AVSpeechUtterance` rate 0.3–1.0.
- **Barge-in:** hold your trigger again mid-reply to interrupt. `Esc` cancels.

## 3. Why this feels realtime without websockets

`DictationController.runAgent` calls `writeStreaming` (SSE `stream:true`), which emits finished sentences (≥20 chars, split on `. ! ? \n`) via `SpeechResponder.speakSentence` while the rest is still generating. Voice overlaps generation — same trick Hermes CLI uses. True full-duplex (listen while speaking in one socket) would need Gemini Live / OpenAI Realtime; not needed for push-to-talk.

## 4. Hermes voice vs clicky voice

Hermes already does realtime voice another way — no rebuild needed if you prefer it:

```bash
hermes
/voice on        # Ctrl+B to talk, silence auto-stops, streaming TTS, barge-in
hermes gateway   # Telegram/Discord: /voice tts ; Discord VC: /voice join
```

Hermes defaults are also $0: `stt.provider: local` (Faster-Whisper, no key) + `tts.provider: edge` (no key). Use clicky for screen-aware paste-where-your-cursor-is; use Hermes for memory, tools, messaging, cron.

## 5. Test on your Mac

1. `open clicky.xcodeproj`, set signing team, `⌘R`.
2. Grant Microphone / Speech Recognition / Accessibility / Screen Recording.
3. Settings → General → Provider Ollama (no key) or paste a Hermes free key.
4. Hold fn → say anything → release (dictate pastes, silent).
5. Hold ⌥ → "reply to this email in my voice" → release (writes, pastes, speaks).
6. Hold ⌥ mid-reply → voice stops, new listen starts.
