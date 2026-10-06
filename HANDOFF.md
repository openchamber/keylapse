# Keylapse development notes

Durable facts for whoever picks this up. What the user sees is in README.md, how the window looks and behaves in DESIGN.md, how to build and check in TOOLING.md; the code is the source of truth for behaviour.

## Environment

- macOS 26 on Apple Silicon, Command Line Tools 27 (Swift 6.4). Full Xcode is not installed and not needed.
- Linker warnings about missing `CommandLineTools/Developer/...` search paths are harmless.
- Local builds are signed with a self-made "Keylapse Local Development" certificate so the signature stays stable between rebuilds and macOS keeps the Accessibility grant. Run `bash scripts/setup-local-signing.sh` once. There is no Developer ID yet; `SIGNING_IDENTITY` and `NOTARY_PROFILE` in `scripts/build.sh` are ready for one.

## Commands

`bun kl-dev` is the menu for the everyday loop (preview, install, build, package, watch, reset); TOOLING.md explains each one, what an agent can verify from a terminal, and the diagnostics flags. The scripts behind it:

```sh
bash scripts/test.sh          # unit tests (Swift Testing; adds the plugin and framework paths the CLT omits)
bash scripts/build.sh         # release build, signed, dist/Keylapse.app and dist/Keylapse.zip
dist/Keylapse.app/Contents/MacOS/Keylapse --self-test   # English ↔ Ukrainian against the real macOS tables
```

## How the code is laid out

Two targets. `KeylapseCore` is pure logic with no AppKit, covered by the unit tests; `Keylapse` is the app around it.

| File | What it owns |
| --- | --- |
| `KeylapseCore/KeyGesture` | Modifier presses → switch, restore, correct. |
| `KeylapseCore/Shortcut` | The two shortcuts: modifier chords and key combinations, sides, validity, storage format. |
| `KeylapseCore/TypedLayout` | Which layout typed a piece of text. |
| `KeylapseCore/LayoutPair`, `LayoutAlphabet`, `LayoutCycle`, `FnSystemAction` | Key-by-key conversion, a layout's letters, the switching order, the macOS Fn setting. |
| `AppDelegate` | Wiring, the menu bar item and its menu, the window, permission requests. No correction logic. |
| `KeyboardMonitor` | The event tap; feeds `KeyGesture` and matches key combinations. |
| `InputSources` | The macOS input sources, their key tables, selecting one, `typedSource`. |
| `CorrectionFlow` | One correction from shortcut to replaced text, with a single `Phase` (idle, reading, choosing, returning, replacing). |
| `SelectionCorrector` | Reads the selection and pastes the replacement; `Clipboard` saves and restores the pasteboard. |
| `DestinationPanel` | The Correct to chooser, the brief notice by the text, and where both appear. |
| `SettingsModel` | Everything the window shows: setup steps, shortcut recording, the welcome word. |
| `SettingsView`, `WelcomeView`, `SettingsStyle` | The window's two pages, the glass, the flower, button styles. |
| `PermissionHint` | The floating tag by System Settings while a permission is awaited. |
| `KeyNames` | Names of keys and shortcuts for keycaps, hints and the tooltip. |
| `Diagnostics` | The `--check-…` flags: developer checks against the live system, listed at the top of the file. |

## Decisions

- **Correction maps physical key positions** using the macOS layout tables. No transliteration, no hard-coded tables. Each layout's alphabet is derived from its own table (base and Shift layers), so any keyboard-layout source can be corrected; there is no per-language list. Composition input methods switch but are never corrected.
- **Which layout typed the text** (`TypedLayout.split`): word by word, letters first, then the layouts the other words were typed on, then the active layout to settle several candidates, then any of them when they all put the word's letters on the same keys (`KeyboardSource.positions`, read with the alphabet), never a guess, and an error always comes before the chooser. Whatever is selected is corrected: `CorrectionFlow` turns the runs into plans (swap the two layouts found, or move everything to another one) and the chooser lists the plans. Try it on the welcome page follows exactly the same rules as a real correction; the demo is never special-cased.
- **Shortcuts**: two independent `Trigger`s, each either a `ModifierChord` (modifier keys held together and released with nothing else: Fn, Control+Fn, Right Command, Control+Option…) or a `KeyCombo` (key code + modifiers, or a bare F-key). The only rule is that they differ (`Shortcut.isValid`). Sides are honoured as recorded; `either` / empty sides mean any side and are what the defaults use. Left and right keys are told apart by the device flag bits (`NX_DEVICEL/R*KEYMASK`, Shift included). `KeyGesture` remembers every modifier held during a gesture and matches the union on release, correction first; Fn alone switches on press (unless Switch on key release) and is put back if more keys join. Any other modifier chord switches on release. Stored as JSON under the `shortcut` default.
- **The event tap** is listen-only while both shortcuts are modifier chords. With any key combination configured, or while a shortcut is being recorded, it runs as `.defaultTap` and swallows the matching key-down; recording through the tap is what lets system-claimed combinations such as ⌘Space be seen (`KeyCombo.systemUse` names them in the row hint). The Fn flag is ignored for F-keys and navigation keys because macOS sets it for them regardless. Actions leave the tap's callback before anything talks to another app, and Accessibility calls time out after a second, so an app that has stopped responding cannot hold up the keyboard.
- **Nothing selected is a silent no-op** for the shortcut, checked before the chooser and before any layout error. `SelectionCorrector.selection` reads the selected text through Accessibility; apps that expose neither the text nor its range (Electron, many web views) get `probeSelection`, a quiet copy that waits at most 0.4 s and restores the clipboard. The menu item says "Select the text you want to fix first." instead, since a click must answer.
- **The replacement is one paste.** The text is already known when the correction starts, so nothing is copied again. What Keylapse writes to the clipboard is marked transient (nspasteboard.org) so clipboard managers leave it out of their history, and the previous content is put back 0.7 s after the paste unless something else has been copied meanwhile. ⌘C and ⌘V are sent on the keys that type those letters in the active layout, so layouts such as Dvorak work.
- **Keylapse's own text field** (the welcome page's Try it) is corrected directly in the field editor, without the clipboard: copy and paste sent to itself do not arrive reliably. The app has an invisible Edit main menu so ⌘A, ⌘C, ⌘V and ⌘Z work in that field.
- **Refused recordings** (a key on its own, the same shortcut as the other row, Caps Lock) flash the caps red and keep recording. There is no list of combinations macOS forbids outright, so nothing reverts automatically.
- **Any shortcut with Fn in it** (`Trigger.usesFn`: Fn alone, Control+Fn, Command+Fn, Fn plus a key) requires the system Fn action to be "Do Nothing": while macOS keeps the key for itself, such chords do not reach Keylapse at all. Keylapse reads that setting but never changes it. The Setup step is always listed and dimmed while no shortcut uses Fn. On the welcome page Use other keys records a switch shortcut and then, if the correction still has Fn, the correction too.
- **Permissions are always read from macOS**, never cached as granted, and re-read every two seconds so a revoked permission stops the event tap promptly. Accessibility alone lets the tap run (macOS treats it as implying keyboard listening): then `CGRequestListenEventAccess` neither prompts nor lists the app under Input Monitoring, while `CGPreflightListenEventAccess` keeps saying no. So the Input Monitoring step counts as done when the tap is running (`SettingsModel.keyboardIsBeingWatched`). Grant… for Input Monitoring still requests access and makes one listen-only tap attempt for the Macs where the flag is really needed. `--permission-report` includes `keyboardTapWorks` to tell the two apart. The welcome page says the same: the Input Monitoring row has no button until Accessibility is granted and reads Usually comes with Accessibility., then Came with Accessibility. beside its checkmark.
- **Grant… for Accessibility** asks macOS (which lists the app and, once, shows its own dialog with an Open System Settings button) and opens the pane itself only if that dialog is not on screen 0.8 s later, detected as a window owned by `universalAccessAuthWarn`. Doing both at once put the dialog and the pane on screen together.
- **The window leads**: `SettingsModel.currentStep` names the one next step and `stepButton` makes only that control prominent and glowing; `hintSwitchOn` is the shared 1.3 s beat (running while the welcome page shows, a step is left, or a permission is awaited).
- **Waiting for a permission**: `SettingsModel.grant(_:)` opens the pane and sets `awaiting`; `refreshState` clears it once macOS reports the step done and calls `onStepCompleted`, on which `PermissionHint.finish` quits System Settings (only if it was not running when the wait began) and brings the window forward. `SettingsRowReplica` is the in-row hint, `PermissionHint` the floating one, placed from `CGWindowListCopyWindowInfo` (which needs no permission) and found by System Settings' process, not its translated name.
- **Removed input methods** (Japanese, Chinese, Korean…) can linger in a running process's `TISCreateInputSourceList` while their helper is still up; `InputSources.reload` cross-checks them against `AppleEnabledInputSources` in `com.apple.HIToolbox` and drops the ones no longer listed, as well as sources macOS reports as not enabled. Keyboard layouts are not filtered this way. `toggle` steps over a source macOS refuses to select, so the cycle never gets stuck in front of one.
- **The chooser and the notice** appear under the selected text (`NSPanel.place(near:)`, from the Accessibility bounds of the selected range, or the focused field when the app reports only that and it is at most 120 pt tall, as Electron message boxes are): below, above when there is no room below, at the pointer when there is room neither way or the app reports nothing.
- **The menu bar menu**: "Keylapse 0.1.0…" (⌘, opens the window; the app has one window, so there is no separate Settings item), the status line, "Correct Selected Text" with the flower and the current correction shortcut, Pause/Resume, then Show Welcome Page (the first-launch page again, nothing else reset) and Quit. The flower shows pause bars while Keylapse is paused or a setup step is left.
- **The welcome page** shows while the `onboarded` default is unset; Start using Keylapse, or closing the window with every step done, sets it. The Try it word comes from `SettingsModel.refreshDemo` (hello mapped from English to the first supported layout whose letters alone identify it).
- **Diagnostics ship in the release build**, because checks that need the app's permissions have to run from the signed, installed bundle. Resources fall back to the source tree only in debug builds.
- DESIGN.md describes Keylapse only, without references to other apps.
- **Icon**: `swift scripts/render-icon.swift <photo> [x y size] --pixel` renders `Resources/AppIcon.png` (blurred photo crop, pixel-art flower; without `--pixel` a smooth outline, with `--background-only <path>` just the square); `bash scripts/make-iconset.sh` builds the iconset and ICNS. Menu bar templates: `swift scripts/render-icon.swift --pixel-glyph Resources/FlowerTemplate.png 21 21 1` and `… FlowerTemplate@2x.png 42 21 1`, the window glyph's grid at 21 pt. The source photo is not in the repository. `Resources/favicon.svg` is the same 21-cell flower as a vector drawn in `currentColor` (dark on light, light on dark); it is not shipped in the app and exists for tools that show a project icon and recolour it to their theme.

## Known limitations

- Correction pastes with ⌘V, so it needs an editable field that accepts a paste. Password fields, terminals and some custom editors do not work.
- An app that takes longer than 0.7 s to act on a paste may get the previous clipboard content instead.
- While a password field has the keyboard (macOS Secure Input), no event tap receives keys, so the shortcuts do nothing there.
- Letters typed via dead keys may be unmapped for some languages; `--check-layouts` prints them as `LIMIT:` lines.
- Only English and Ukrainian have been verified end to end in an editor.

## Not yet verified by hand

The unit tests, the table checks and the window previews pass; these need a person at the keyboard:

- Correction in an app that hands its selection over (Notes, TextEdit) and in one that does not (an Electron app), now that the replacement is a single paste.
- Correction with Dvorak active.
- A selection typed on two layouts in an app other than TextEdit, and the swap row in the chooser with three or more layouts.
- Modifier chords other than Fn / Control+Fn, and key combinations, on a physical keyboard.
- With two displays: the window joining the macOS Accessibility dialog on the other display, System Settings being brought to Keylapse's display on the Fn step, the floating hint hiding under the open Fn menu.
- Any macOS older than 26; the deployment target is 13.

## Planned next

1. A tester's copy from `bun kl-dev package`, then the list above.
2. Before a public release: a Developer ID and notarisation (`scripts/build.sh` is ready for both), and a licence.

Not planned: Caps Lock as a shortcut (recording refuses it with a reason), double-tap modifiers, flag emoji next to layouts (a language is not a country; the accent dot stays), a button that revokes Keylapse's own permissions (they belong to macOS), a Set up later button, going straight from Accessibility to the Fn step without closing System Settings.
