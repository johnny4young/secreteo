# Secreteo

Global, local, private dictation from your Mac's menu bar.

Hold a key, speak, and the text lands in whatever app you are using. Speech recognition runs on your Mac.

## Install

```sh
brew install --cask johnny4young/tap/secreteo
```

Or download the disk image from [the latest release](https://github.com/johnny4young/secreteo/releases/latest). Updates arrive through the app.

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
