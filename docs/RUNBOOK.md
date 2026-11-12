# Release runbook

The manual gates of [RELEASING](RELEASING.md#manual-gates-on-the-release-mac), as steps on the release Mac. Each step says what you should see and which [PARITY](PARITY.md) row or [GAPS](GAPS.md) entry its result updates. Write results in a docs PR.

Before any step that runs the app, add a line to the physical test reservations, and remove it after. Use synthetic text and the disposable build where a step says so; never the real Portavoz library.

## 0. Build

```sh
make install
```

You should see `/Applications/Secreteo Dev.app`. Steps that say **release build** use the DMG from the draft release instead.

## 1. Models

| Step | Expect | Updates |
|---|---|---|
| Fill a scratch store and run `make test-model-gated` as in [RELEASING](RELEASING.md#model-gate) | A `PASS` line for every lane | Release contract: memory |
| Open Settings > Speech Models | Parakeet v3 and the voice detector listed with their sizes | Model download and storage |

## 2. Spikes

| Step | Expect | Updates |
|---|---|---|
| [Spike 1: two apps at once](spikes/two-apps-at-once.md) | Every threshold there passes | G1, One owner per Mac |
| [Spike 2: a clean account](spikes/clean-account.md), **release build** | All seven steps pass | G13, Permissions on a clean account |

## 3. Triggers

Dictation on, Secreteo the owner. Target: TextEdit, a new document.

| Step | Expect | Updates |
|---|---|---|
| Press ⌃⌥⌘D, say "the meeting moves to Monday", press it again | The sentence lands in TextEdit once, capitalized | Global shortcut |
| Set Fn as push to talk; hold it, speak, release | The words land once when you release | Push to talk, Fn and modifiers |
| Set a mouse button; hold it, speak, release | Same as Fn | Push to talk, mouse |
| Select a word in TextEdit, press ⌃⌥⌘R | The selection is rewritten in place | Selection Rewrite |
| Turn on Correct the Last Dictation by Voice; dictate "change Monday to Friday" | The last dictation changes in place | Spoken correction in delivery |

## 4. Delivery

| Step | Expect | Updates |
|---|---|---|
| Dictate into Notes, Slack or another Electron app, and Safari's address bar | Text lands once in each, nothing extra on the clipboard | Readback and verified delivery, G9 |
| Copy an image, dictate, then paste with ⌘V | The image comes back after 1.5 s | Clipboard restored, G9 |
| Dictate with the caret mid-sentence after a lowercase word | No capital and one space | Capitals and spacing from the caret |
| Dictate into a password field | Nothing is pasted; the words wait in the panel | Retry with no double paste |
| Start a dictation, switch apps before it pastes, then press Retry in the panel | The words land once, in the app you retried in | Retry with no double paste, Text recovery |
| Start a dictation and press Esc while it prepares, then again during Stop | No text lands and the next dictation starts clean | Cancel during prepare and during Stop |
| Revoke Microphone in System Settings while Secreteo runs, then dictate | Secreteo says what is missing; granting it again works without a relaunch | Permissions revoked |
| Unplug a USB microphone mid-dictation | The words so far stay in the panel to copy | Microphone capture, G10 |
| Open the menu from another app and choose Dictate | Focus returns to that app and the words land there | G11 |

## 5. Ownership

With the disposable Portavoz build of Spike 1:

| Step | Expect | Updates |
|---|---|---|
| Turn on dictation in both apps | Only one owns the shortcut; the other says who does | One owner per Mac |
| Take ownership in the other app | The handoff completes within 2 s and the first app stops answering | One owner per Mac |
| Quit the owner with Activity Monitor's Force Quit | The other app can take ownership after its recovery | One owner per Mac |

## 6. Updates and install, **release build**

| Step | Expect | Updates |
|---|---|---|
| `brew install --cask johnny4young/tap/secreteo` on an account without it | Installs, opens, no Gatekeeper warning | Clean Homebrew install |
| From the previous version, Check for Updates | Sparkle installs the new version and relaunches | A real Sparkle update |
| Accept an update while a dictation is still pasting | The relaunch waits for the paste | G7 |

## 7. VoiceOver

Turn on VoiceOver and go through Settings, the menu, onboarding and Dictation History. Every control reads a name and a state, and none is skipped. Updates: release contract.
