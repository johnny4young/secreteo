# Secreteo

Global, local, private dictation from your Mac's menu bar.

Hold a key, speak, and the text lands in whatever app you are using. Speech recognition runs on your Mac.

## Install

```sh
brew install --cask johnny4young/tap/secreteo
```

Or download the disk image from [the latest release](https://github.com/johnny4young/secreteo/releases/latest). Updates arrive through the app.

## What it does

- **Triggers:** hold-to-talk with `Fn`, a right modifier key, a mouse button, or a held shortcut, or toggle with the global shortcut (`⌃⌥⌘D`).
- **On-device speech engines:** Parakeet, Parakeet Ultra, or Apple Speech in Spanish and English (including code-switched Automatic), releasing idle weights automatically when memory is tight.
- **Clean mode:** removes filler words, formats spoken punctuation and self-corrections (English and Spanish), expands multiline voice snippets, and normalizes Personal Vocabulary with bilingual phonetic matching.
- **Application Profiles:** per-app Chat, Email, and Code / Terminal presets that protect `camelCase`, `snake_case`, and CLI flags.
- **Local Polish & Selection Rewrite:** optional refinement via Apple Intelligence or a local Ollama server (`http://localhost:11434`).
- **Adaptive learning:** voice corrections, 1-click **Teach Replacement** from History, and opt-in post-paste edit learning.
- **Private History & integrations:** optional local database with semantic search, Apple Shortcuts, and a read-only MCP helper (`secreteo-mcp`).

## Requirements

- macOS 26 or later
- Apple silicon. Measured only on an M4 Max with 36 GB of memory; smaller Macs are unmeasured.

## What leaves your Mac

Nothing by default. Audio and text stay on the device.

| Network use | When |
|---|---|
| Speech model download from Hugging Face | Once per model, after you agree |
| Apple Speech language download from Apple | Once per language, when you pick Apple Speech and macOS lacks it |
| Update check through Sparkle | On schedule or when you ask |
| Polish through Ollama | Only if you turn it on, to the local Ollama server on this Mac (`http://localhost:11434`) |

## Permissions

| Permission | Why |
|---|---|
| Microphone | To hear you while you dictate |
| Accessibility | To detect the trigger key and place text in the active app |

## Coming from Portavoz

Secreteo takes over the dictation that started in [Portavoz](https://github.com/johnny4young/portavoz), which stays focused on meetings. History does not transfer, and macOS asks for both permissions again because this is a new app. Shortcuts and MCP clients have to be set up again by hand.

Update Portavoz to 1.4 or later, or turn its dictation off: an older Portavoz with dictation on keeps Secreteo from dictating, so the two never answer the same key.

## Build from source

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Third-party components are listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
