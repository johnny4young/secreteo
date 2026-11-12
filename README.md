# Secreteo

Global, local, private dictation from your Mac's menu bar.

Hold a key, speak, and the text lands in whatever app you are using. Speech recognition runs on your Mac.

> **Status:** in development. There is no release yet.

## Install

Available after the first release:

```sh
brew install --cask johnny4young/tap/secreteo
```

## Requirements

- macOS 26 or later
- Apple silicon, with 16 GB of memory recommended. 8 GB has not been measured.

## What leaves your Mac

Nothing by default. Audio and text stay on the device.

| Network use | When |
|---|---|
| Speech model download from Hugging Face | Once per model, after you agree |
| Update check through Sparkle | On schedule or when you ask |
| Polish through Ollama | Only if you configure it, to the address you choose |

## Permissions

| Permission | Why |
|---|---|
| Microphone | To hear you while you dictate |
| Accessibility | To detect the trigger key and place text in the active app |

## Coming from Portavoz

Secreteo takes over the dictation that started in [Portavoz](https://github.com/johnny4young/portavoz), which stays focused on meetings. History does not transfer, and macOS asks for both permissions again because this is a new app. Shortcuts and MCP clients have to be set up again by hand.

## Build from source

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Third-party components are listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
