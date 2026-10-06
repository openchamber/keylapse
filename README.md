<p align="center"><img src="docs/icon.png" width="128" alt=""></p>
<h1 align="center">Keylapse</h1>
<p align="center">Fixes text typed in the wrong layout.</p>
<p align="center">
  <a href="https://github.com/openchamber/keylapse/releases/latest"><img src="https://img.shields.io/github/v/release/openchamber/keylapse?label=release&color=4b8bf5" alt="Latest release"></a>
  <a href="https://github.com/openchamber/keylapse/releases"><img src="https://img.shields.io/github/downloads/openchamber/keylapse/total?color=4b8bf5" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-4b8bf5" alt="macOS 13 or later">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/openchamber/keylapse?color=4b8bf5" alt="GPL-3.0"></a>
</p>

You type a whole sentence, look up, and it reads `ghbdsn цщкдв`. Wrong layout again. Keylapse is a menu bar app for the Mac that fixes this: select the text, press `Control + Fn`, and it becomes `привіт world`. Both halves, each the right way round. No retyping, no dictionaries, nothing leaves your Mac.

`Fn` on its own switches layouts. Any layout macOS knows is fine.

![A sentence typed on two layouts, selected and corrected with one key press](docs/correction.gif)

## Get started

1. Download `Keylapse-<version>.zip` from the [latest release](https://github.com/openchamber/keylapse/releases/latest), unzip it, drop Keylapse into Applications and open it. Or let Homebrew do the dropping:

   ```sh
   brew install --cask openchamber/tap/keylapse
   ```

   Either way, the welcome window walks you through the rest.

   ![The Keylapse window on first launch: setup steps, a word to try the correction on, and the shortcut keys](docs/welcome.png)

2. Click **Grant…** beside Accessibility and allow Keylapse in the macOS settings that open. Input Monitoring usually comes along for free. If its row still asks, grant it too.
3. If Setup asks you to set Fn to **Do Nothing**, click **Open Settings** and choose that in Keyboard settings. Another Fn language switcher running? Quit it, or the two will fight over the key.
4. Under **Try it** the word is already selected. Press `Control + Fn`, watch it turn into `hello`, then click **Start using Keylapse**. The flower in the menu bar brings the window back; the first item in its menu opens it.

Fn is sacred on your Mac? Click **Use other keys** on that step and press what you like, Right Command for instance. If the correction keys have Fn in them too, the same row asks for new ones. Nothing in macOS changes. Any shortcut with Fn in it, alone or with other keys, works only while macOS has Fn set to Do Nothing.

## Everyday use

- **Switch layouts.** Press `Fn`. It cycles through every input source enabled in macOS, input methods included.
- **Fix text.** Select it, hold `Control`, tap `Fn`, let go. Nothing selected, nothing happens.
- **Undo.** `⌘Z` in your editor, like any other edit.

### Shortcuts you choose

Click the drawn keys of a row under **Shortcuts** and press what you want instead. The two shortcuts are independent; the only rule is that they differ.

- Modifier keys on their own: one or several held together and released without any other key. Fn, Right Command, Control-Fn, Control-Option. Fn alone switches the moment you press it. Other modifiers switch when you let go, and a regular key pressed meanwhile cancels the switch, so Option-E still types é.
- A combination: any key with a modifier, Option-Space or Control-Shift-L, or an F-key on its own. Keylapse takes these before the app in front sees them. You can even grab one macOS already uses, Command-Space say; the row tells you what stops working while Keylapse runs.

Left and right are told apart as you recorded them, so Left Command-Space can switch while Right Command-Space corrects. A lone key (F-keys aside) is refused, and so is the same shortcut for both; the keys flash red and the row says why. **Reset** brings back Fn and Control-Fn.

![The Keylapse window: setup, behavior, the list of layouts and the two shortcuts](docs/settings.png)

### The rest

With two layouts, correction is instant. With more, a small **Correct to** list asks where. Layout variants, U.S. and Dvorak say, count separately.

The welcome window comes back any time: click the flower, then **Show Welcome Page**.

Keylapse can start at login, and it can correct the selection when you click the flower, in which case the menu opens on right-click. Both live under **Behavior**. Correction goes through the clipboard: what you had copied is put back afterwards, and clipboard managers are asked to look away.

Keylapse keeps itself up to date. It checks GitHub when it starts and once a day after that, and **Check for Updates…** in the flower's menu checks right now. When there is a new version, a window says what changed and offers to install it. Nothing downloads before you agree, and that check is the only thing Keylapse ever sends anywhere. Your text is not in it.

## Languages

Any keyboard layout macOS can describe as a key table works, in any language. Keylapse reads each layout's own letters and maps them by physical key, so there is no list of supported languages to get onto. It needs two such layouts. Input methods that compose text, such as Japanese, Chinese or Korean, are marked **Switching only**: the switch key still reaches them, and text typed on your other layouts is corrected while they are active.

Which layout typed the text is worked out from the letters, word by word. A layout that cannot type one of a word's letters is out. One left, that is it, whatever is active, so you need not switch back first. Several left (plain Latin letters fit English and German alike), and it takes the layout the neighbouring words were typed on, then the active one. When the candidates would give the same result anyway, because those letters sit on the same keys, it just goes ahead. Only when they would differ does Keylapse ask you to switch to the layout you typed on, rather than guess.

Whatever you select is corrected. A sentence typed half on one layout and half on another is swapped word by word, and a word that changes alphabet midway is split there. With more than one way to correct the selection, the **Correct to** list asks; whatever you choose there works. For text from two layouts the first choice swaps them (English ↔ Ukrainian) and each other choice moves the whole text to that layout.

![Choosing the layout to correct to from the Correct to list with the arrow keys](docs/choose-layout.gif)

English and Ukrainian are tested end to end. Other languages should work and are waiting for a tester. Letters typed through dead keys cannot always be corrected.

Correction needs an editable field that accepts a paste. Password fields and some editors do not.

## Questions people ask

**Nothing happens when I press Fn.** macOS is keeping the key for itself. Set Fn to Do Nothing in Keyboard settings (the Setup step points there), or give Keylapse other keys with Use other keys. Another layout switcher that also sits on Fn has to go.

**It does nothing in a password field, or in my terminal.** On purpose, and not up to Keylapse. While a password field has the keyboard, macOS lets no app see keys. Terminals and some editors do not take a paste, and the correction is a paste.

**Does it work in Slack, VS Code, the browser?** Yes. Apps built on web views do not say what is selected, so Keylapse asks with a quiet copy, waits at most 0.4 s, and puts your clipboard back. If an app will not answer a copy either, select the text and try again.

**Why Accessibility and Input Monitoring?** Accessibility is how Keylapse reads the selection and replaces it. Input Monitoring is how it sees the shortcut keys; on most Macs it comes with Accessibility and the row says so.

**What leaves my Mac?** One request a day to GitHub to ask for a newer version. No text, ever.

## Building from source

Keylapse is a Swift package with no dependencies beyond Sparkle, which it fetches. With Xcode or the Command Line Tools installed:

```sh
bash scripts/test.sh    # unit tests
bash scripts/build.sh   # dist/Keylapse.app, signed with a local certificate (run scripts/setup-local-signing.sh once)
```

`bun kl-dev` (or `node scripts/kl-dev.mjs`) lists the everyday commands; TOOLING.md explains them, and HANDOFF.md and DESIGN.md describe how the app and its window are meant to work.

## License

Keylapse is free software under the GNU General Public License, version 3: see LICENSE. Copyright 2026 Iuliia Ivashko.
