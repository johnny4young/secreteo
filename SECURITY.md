# Security Policy

## Reporting a vulnerability

Do not open a public issue for security problems. Use GitHub's [private vulnerability reporting](https://github.com/johnny4young/secreteo/security/advisories/new) with details and reproduction steps. You will get an acknowledgment within 72 hours.

## Design commitments

These apply from the first release:

- Audio and dictated text stay on the device by default.
- Audio and dictated text never appear in logs.
- A menu bar agent with microphone and Accessibility access never runs without a visible icon. If the icon goes away, the app cancels any active session and quits.
- There is no URL scheme, so a web page cannot trigger the microphone.
- Model downloads are verified against pinned SHA-256 checksums compiled into the signed binary.
- Polish through Ollama is opt-in, goes to the address the user configures, and leaves a content-free receipt.
- The MCP interface is a local process over stdio. It opens no network listener and is read-only.

## macOS containment boundary

The app is Developer ID signed, uses the Hardened Runtime, is notarized, and is **not** App Sandbox-enabled. It requests only the microphone entitlement, and macOS still asks for Microphone and Accessibility permission.

The shared model store and the cooperative dictation lock protect against corruption and races between cooperating clients. They are not a security boundary against a malicious process running as the same user.
