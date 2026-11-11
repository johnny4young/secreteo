# Changelog

User-visible changes, newest first. Dictation history before Secreteo is in [Portavoz's changelog](https://github.com/johnny4young/portavoz/blob/main/CHANGELOG.md).

## Unreleased

- ♻️ **Updates during dictation**: an accepted update's relaunch hook waits for dictation, clipboard cleanup, and pending history and statistics saves before continuing.

- 🎙️ **Sleep during dictation**: cancel preparation and capture when the Mac sleeps, keep recognized words available to copy, and prevent those cancelled sessions from pasting later.
- 🔎 **Search errors**: cancelled searches can be retried without a false error, and older searches no longer replace the latest error state.
- 🔎 **History search**: keep results ordered and up to date after saving or deleting, and continue indexing older dictations when some cannot be processed.
- 🔎 **Search by meaning**: after the dictations that hold your words, Dictation History lists those that say the same thing in other words, in English or Spanish. It runs on this Mac and uses the language model macOS already has.
- 🎙️ **Shared voice detector**: another app cannot remove Silero while dictation loads it or checks speech, including when a check is being cancelled.
- ♻️ **Shared speech models**: another app cannot remove Parakeet's files while Secreteo is loading or using them.
- 🎙️ **Speech engine**: choose Parakeet, Parakeet Ultra or Apple Speech in Settings. Ultra downloads only when you ask, and dictation uses Parakeet until it is ready. Apple Speech never downloads Parakeet.
- ⏹️ **Faster stop on slow displays**: the audio meter freezes when you press Stop, so the words arrive sooner.
- 🤖 **Agents read your history**: a read-only MCP server ships inside Secreteo. Turn on “Let Agents and Shortcuts Read History” in Settings, then add `/Applications/Secreteo.app/Contents/Helpers/secreteo-mcp` to your MCP client. Clients set up for Portavoz have to be pointed at Secreteo by hand.
- 🗂️ **Text mode per app**: give an app its own text mode, recipe and translation in Settings. Importing from Portavoz brings them too.
- ✍️ **Rewrite the selection**: select text in any app, choose Polish, a recipe or say how, check the preview and press Return to replace it. From the menu, or with ⌃⌥⌘R once you turn it on.
- 📊 **Dictation statistics**: if you turn them on, see dictations, words, speaking time and time saved for the last 7 or 30 days, and where you dictate most. They count, never keep what you said.
- 📶 **Download progress**: Settings shows how much of the speech model has downloaded.
- 🧾 **Polish recipes and translation in Settings**: write your own recipes for Polish, pick one as the default, and translate dictation into English or Spanish as it is pasted.
- 🔎 **Search your dictations**: find a saved dictation by its words, with or without accents, while you type.
- ✨ **Polish**: choose Polish as the text mode, and polish with Apple Intelligence or a model in Ollama, both on this Mac.
- ⚡ **Shortcuts actions**: Dictate and Paste Last Dictation run from Shortcuts, and refuse while another app handles dictation. Search Dictations and Open Dictations read the history you share. Shortcuts built with Portavoz's actions have to be rebuilt with Secreteo's.
- 🗂️ **Dictation history**: save your dictations on this Mac if you turn it on, keep them 7, 30 or 90 days, filter them, and copy or delete them from Dictation History in the menu.
- 📥 **Settings from Portavoz**: import your dictation settings from Portavoz in Settings, after seeing what will change.
- ♻️ **Models from Portavoz**: when Portavoz already downloaded the speech model, Secreteo copies it instead of downloading it again.
- 👋 **First-run setup**: turn on dictation and grant its permissions, prepare the speech model for this Mac, and try it, all in three steps.
- 🪶 **Lighter model check**: checking the speech model at launch no longer takes hundreds of megabytes of memory for a moment.
- 🧠 **Model memory**: free the speech model soon after dictating, or load it at launch so the first dictation starts faster. Secreteo also lets it go when the Mac runs low on memory.
- 📋 **Paste the last dictation with a shortcut**: turn on ⌃⌥⌘V in Settings to paste it again from any app.
- 🎤 **Try dictation in Settings**: dictate into a field inside the app, with no Accessibility permission and nothing saved.
- ⚙️ **Dictation settings**: choose your shortcut, a mouse button or a key to hold, the language, the microphone, and text replacements.
- ⏯️ **Model downloads resume**: an interrupted download continues from the next file instead of starting over.
- 🎙️ **Menu bar app**: Secreteo lives in the menu bar, with Settings and Open at Login.
- 🔄 **Quiet updates**: a new version shows as a menu row, and never interrupts you.
