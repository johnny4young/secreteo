# Spike 2: a clean account

**Question:** does a menu bar agent activate, keep its icon and retry push to talk on a macOS account that has never run Secreteo? ([G13](../GAPS.md#g13-an-icon-loss-no-event-announces))

**Status:** thresholds written 2026-11-11, before any measurement. Not run yet.

## Setup

- A new standard macOS user account on the release Mac, with no Secreteo preferences, permissions or models.
- The signed and notarized `0.1.0` DMG from the draft release, or `make install` when the draft does not exist yet. Note which.
- A line in `STATUS.md` before starting, removed after.

## Steps and thresholds

| # | Step | Passes when |
|---|---|---|
| 1 | Open the DMG and drag Secreteo to Applications, then open it | Gatekeeper opens it without a warning about an unidentified developer; the menu bar icon appears within 5 s; no Dock icon |
| 2 | Click the menu bar icon | The menu opens on the first click, every time in 10 tries |
| 3 | Go through onboarding | Microphone and Accessibility each prompt once; the model downloads after you agree; practice completes |
| 4 | Hold the trigger before Accessibility is granted, then grant it | Push to talk works on the next hold, with no relaunch and no activation of Secreteo |
| 5 | Hide the menu bar icon with the per-app Menu Bar setting of macOS 26, then show it again | The watchdog brings the icon back within 7 s, or Secreteo stays reachable from Settings |
| 6 | Connect and disconnect a second display | The icon is visible on the menu bar after each change |
| 7 | Log out and in with Open at Login on | Secreteo starts, with its icon, without a second instance |

Every step must pass. Write down the time and what you saw for each.

## Result

Not measured yet.
