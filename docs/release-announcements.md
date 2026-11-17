# Release announcements

Ready-to-paste texts for each Secreteo release, newest first. Copy, adjust, post.

## Introducing Secreteo

A first post that shows what Secreteo is, not what one release changed. Post the thread, or the single post on its own.

### X / Bluesky thread 1/6 — 186 characters · attach a short video of the capsule while dictating

Meet Secreteo: hold a key, speak, and your words land in whatever Mac app you're using.

Speech recognition runs on your Mac. Nothing leaves it by default. Free and open source (MIT).

🧵

### X / Bluesky thread 2/6 — 219 characters

What makes it different: it never needs the cloud.

Parakeet or Apple Speech run on-device, in English and Spanish. The only network calls are a one-time model download, update checks, and Ollama if you point it at one.

### X / Bluesky thread 3/6 — 187 characters · attach a screenshot of the capsule with words in italics

It shows you what it hears.

One dark capsule sits under your caret, and its light rises with your voice. Words you're still saying appear in italics, then stand upright once they settle.

### X / Bluesky thread 4/6 — 146 characters

It doesn't lose your words.

If a field can't take the text, a card holds it with Reinsert first. Trigger with Fn, a mouse button or any shortcut.

### X / Bluesky thread 5/6 — 243 characters

Beyond typing:
• Polish with Apple Intelligence or a local Ollama model
• Rewrite Selection: select text, say how
• Optional history you can search by meaning
• Shortcuts actions and a read-only MCP server, so agents can search your dictations

### X / Bluesky thread 6/6 — 243 characters

Honest about limits: Apple silicon and macOS 26, measured only on an M4 Max. Some paths are covered by tests but not yet checked by hand in other apps. That list is public.

brew install --cask johnny4young/tap/secreteo
https://secreteo.pages.dev

### X / Bluesky single post — 260 characters

Secreteo: hold a key, speak, and the text lands in any Mac app. Recognition runs on-device, nothing leaves your Mac by default. A capsule under your caret shows your words as you say them. Polish, Rewrite Selection, MCP for agents. MIT. https://secreteo.pages.dev

### Links

- Site: https://secreteo.pages.dev
- Known limits: https://github.com/johnny4young/secreteo/blob/main/docs/GAPS.md
- `brew install --cask johnny4young/tap/secreteo`

## v1.1.0 — 2026-11-16

Secreteo 1.1 redraws every surface: one dark capsule under your caret that rises with your voice, and the same look across the menu, Settings, History and setup.

![Secreteo icon](https://secreteo.pages.dev/icon.png)

### X / Bluesky — 263 characters

Secreteo 1.1: dictation is now one dark capsule under your caret. Its light rises with your voice, words still being said show in italics, then settle. The menu, Settings, History and setup are redrawn to match. Still on-device, still MIT. https://secreteo.pages.dev

### Hacker News

**Title:** `Secreteo 1.1 – the on-device Mac dictation app gets a look of its own`

**Text:**

Secreteo 1.0 moved dictation over from Portavoz and wrote down every limit it still had. 1.1 changes nothing about where your audio goes. It changes everything you see.

The panel is now one dark capsule under the caret. Its light follows your voice, and the words you are still saying appear in italics, then stand upright once the recognizer settles them. After an insertion it shrinks to a pill that says how many words went where, then leaves. When text did not land, it opens a card as tall as the words, with Reinsert first if the field can take them again. The small indicator is just two parentheses, 30 × 24 pt, showing each state as a face.

The rest follows: a menu that works as a small dashboard (state, the real keys, the last dictation, words over seven days), Settings in five tabs with a readiness header, History as a day log, Rewrite Selection as a card, and a setup that ends with a real first dictation instead of a checklist.

Every control in the new UI has an XCUITest assertion. The 15 declared limits from 1.0 are unchanged: paths covered by tests but not yet checked by hand against other apps, measured only on an M4 Max with 36 GB.

### Reddit (r/macapps)

**Title:** `Secreteo 1.1: redesigned on-device dictation for the Mac menu bar`

**Text:**

Free, MIT, recognition on your Mac. 1.1 is a full redesign:

- One dark capsule under the caret that rises with your voice
- Results sized to their words, with Reinsert first when text didn't land
- Menu as a small dashboard, Settings in five tabs, History as a day log
- Menu bar icon that shows what dictation is doing
- Setup that ends with a real first dictation

Same limits as 1.0: Apple silicon and macOS 26, measured only on an M4 Max 36 GB. Update from the menu or `brew upgrade --greedy`.

### Platform notes

> Homebrew users need `brew upgrade --greedy`: the cask updates itself, so plain `brew upgrade` skips it.

### Links

- Release: https://github.com/johnny4young/secreteo/releases/tag/v1.1.0
- Site: https://secreteo.pages.dev
- Known limits: https://github.com/johnny4young/secreteo/blob/main/docs/GAPS.md
- `brew install --cask johnny4young/tap/secreteo`

## v1.0.0 — 2026-11-15

Secreteo 1.0: global dictation from the Mac menu bar, fully moved over from Portavoz, with every limit it still has written down.

![Secreteo icon](https://secreteo.pages.dev/icon.png)

### X / Bluesky — 246 characters

Secreteo 1.0 is out. Hold a key, speak, and the text lands in whatever Mac app you're using. Recognition runs on your Mac, nothing leaves it by default. Apple silicon, macOS 26, MIT. Known limits are published, not hidden. https://secreteo.pages.dev

### Hacker News

**Title:** `Show HN: Secreteo 1.0 – local, private dictation from the Mac menu bar`

**Text:**

Secreteo is a menu bar app for macOS 26: hold Fn, a mouse button or a shortcut, speak, and the text is pasted into whatever app has focus. Speech recognition runs on the Mac with Parakeet (through FluidAudio) or Apple Speech. Audio and text stay on the device unless you opt in to something, and the only network calls are speech model downloads, Sparkle's update check, and Ollama at an address you choose.

It started as the dictation half of Portavoz, my meeting app. Splitting it out meant porting it file by file, and every capability only counts as ported when a test in the new repo proves it. The parity matrix is public, and so is the part I'm least proud of: fifteen rows (the global shortcut in another app, the clipboard restore, caret-aware capitals, Accessibility readback and a few more) are covered by tests but have not been checked by hand on a real Mac against other apps. They are declared limits, each linked to its gap entry.

Same honesty on hardware: it needs Apple silicon, and the only machine it has been measured on is an M4 Max with 36 GB. I don't claim a minimum I haven't measured. Core ML also compiles its own copy of the model per app, about 14 seconds on that M4 Max, so first launch shows a warm-up step.

Other bits: optional history with retention and full erase, a read-only MCP server so agents can search your dictations if you turn it on, Shortcuts actions, Polish with Apple Foundation Models or a local Ollama model, and English and Spanish throughout. Releases are signed, notarized, and update through Sparkle or Homebrew.

### Reddit (r/macapps, r/LocalLLaMA)

**Title:** `Secreteo 1.0: free, open-source, on-device dictation for the Mac menu bar`

**Text:**

Hold a key, speak, and the text goes into whatever app you're using. Everything runs on your Mac.

- Parakeet or Apple Speech, on-device, English and Spanish
- Trigger with a shortcut, Fn or a mouse button
- Optional history with retention, opt-in statistics, Shortcuts actions
- Read-only MCP server for agents, off until you enable it
- Polish with Apple Intelligence or a local Ollama model
- MIT, notarized, updates via Sparkle or Homebrew

Limits: Apple silicon and macOS 26 only, measured only on an M4 Max 36 GB, and some paths are covered by tests but not yet checked by hand in other apps. The list is public.

### Platform notes

> Not tagged yet. Publish v1.0.0 before posting. If you use Portavoz, update it to 1.4 or later, or turn its dictation off: an older Portavoz with dictation on keeps Secreteo from dictating.

### Links

- Release: https://github.com/johnny4young/secreteo/releases/tag/v1.0.0
- Site: https://secreteo.pages.dev
- Known limits: https://github.com/johnny4young/secreteo/blob/main/docs/GAPS.md
- `brew install --cask johnny4young/tap/secreteo`

## v0.1.2 — 2026-11-15

With Prewarm on, a speech model unloaded under memory pressure loads again once the pressure ends.

### X / Bluesky — 225 characters

Secreteo 0.1.2: with Prewarm on, the speech model comes back by itself once macOS stops being short on memory, so your next dictation doesn't wait for it. Update from the menu or brew upgrade --greedy. https://secreteo.pages.dev

### Links

- Release: https://github.com/johnny4young/secreteo/releases/tag/v0.1.2
- Site: https://secreteo.pages.dev
- `brew install --cask johnny4young/tap/secreteo`

## v0.1.1 — 2026-11-14

Shortcuts and agents can now find dictations by meaning, not only by their words.

### X / Bluesky — 228 characters

Secreteo 0.1.1: Shortcuts and the MCP server's search_dictations now list dictations that say the same thing in other words, after the exact matches. On-device, using the language model macOS already has. https://secreteo.pages.dev

### Links

- Release: https://github.com/johnny4young/secreteo/releases/tag/v0.1.1
- Site: https://secreteo.pages.dev
- `brew install --cask johnny4young/tap/secreteo`

## v0.1.0 — 2026-11-13

First release: dictate into any Mac app with a shortcut, Fn or a mouse button, with recognition running on the Mac.

### X / Bluesky — 238 characters

Secreteo 0.1.0: dictation from the Mac menu bar. Hold Fn, a mouse button or a shortcut, speak, and the text lands in the app you're using. Parakeet or Apple Speech, on-device. Optional history, MCP for agents, MIT. https://secreteo.pages.dev

### Hacker News

**Title:** `Show HN: Secreteo – on-device dictation for any Mac app`

**Text:**

Secreteo takes over the dictation that used to live inside Portavoz, my meeting app, so that Portavoz can stay about meetings. It's a menu bar app: hold a trigger, speak, and the text is pasted where your cursor is.

The interesting constraint is two apps sharing one Mac. Both can dictate, so they agree through a small ownership protocol on who answers the keys, and they share one copy of the speech model on disk instead of downloading it twice. A Portavoz older than 1.4 doesn't speak the protocol, so with its dictation on, Secreteo refuses to dictate rather than fight it.

Recognition runs locally with Parakeet or Apple Speech. History is off by default; when on, it has retention and an erase that leaves no words in the files. A read-only MCP server ships inside the app for agents, also off until you turn it on.

It needs Apple silicon and macOS 26, and this first release has only been measured on an M4 Max.

### Reddit (r/macapps)

**Title:** `Secreteo: free, open-source, local dictation for macOS`

**Text:**

Menu bar app: hold a key, speak, text appears in the current app. Recognition is on-device (Parakeet or Apple Speech), English and Spanish.

- Shortcut, Fn or mouse-button triggers
- Optional history and statistics, both off by default
- Shortcuts actions and a read-only MCP server
- Polish with Apple Intelligence or Ollama, on your Mac

Apple silicon and macOS 26 only. MIT licensed.

### Links

- Release: https://github.com/johnny4young/secreteo/releases/tag/v0.1.0
- Site: https://secreteo.pages.dev
- `brew install --cask johnny4young/tap/secreteo`
