# Keylapse

Switch keyboard layouts and fix text typed in the wrong one. For macOS 13 or later; tested on macOS 26.

Select `ghbdsn`, press `Control + Fn`, and get `привіт` without retyping. It works both ways: `руддщ` becomes `hello`.

## Get started

1. Move Keylapse to Applications and open it. A welcome window appears.
2. Under **Setup**, click **Grant…** beside Accessibility and allow Keylapse in the macOS settings that open. A checkmark appears once granted, usually beside Input Monitoring too, since Accessibility covers it; if that row still asks, click its **Grant…** as well.
3. If Setup asks you to set Fn to **Do Nothing**, click **Open Settings** and choose that action in macOS Keyboard settings. A checkmark appears once ready. Quit any other Fn language switcher.
4. Under **Try it**, the word is already selected: press `Control + Fn` and watch it become `hello`. Then click **Start using Keylapse**. Keylapse follows the input sources enabled in macOS; click the flower in the menu bar, then **Keylapse** at the top of the menu, to open the window again.

Prefer to keep the system Fn behaviour? In the welcome window click **Use other keys** beside that step and press the key or combination you want for switching, for example **Right Command**; if the correction shortcut also has Fn in it, the same row then asks for new correction keys. The step is done without changing anything in macOS. Any shortcut with Fn in it, on its own or with other keys, works only while macOS has Fn set to **Do Nothing**. Later, the same can be done in the **Shortcuts** section by clicking the drawn key.

## Everyday use

- **Switch layouts:** press `Fn` to cycle through all your enabled macOS input sources.
- **Fix text:** select it, hold `Control`, press `Fn`, then release both keys. With nothing selected the shortcut does nothing.
- **Undo:** press `⌘Z` in your editor.

Both shortcuts can be changed in the Keylapse window under **Shortcuts**: click the drawn keys of a row, then press what you want instead. The two shortcuts are independent; the only rule is that they differ.

- **Modifier keys on their own:** one or several held together and released without any other key, such as Fn, Right Command, Control-Fn or Control-Option. Fn alone switches as soon as you press it; any other modifier keys switch when you release them, and pressing a regular key with them cancels the switch, so shortcuts such as Option-E keep working.
- **A combination:** any key with a modifier, such as Option-Space or Control-Shift-L, or an F-key on its own. Combinations are intercepted, so the app in front does not also receive them. You can take a combination macOS already uses, such as Command-Space; the row says what stops working while Keylapse runs.

Left and right keys are told apart as you recorded them: a shortcut recorded with the left Command key does not answer to the right one, so Left Command-Space can switch while Right Command-Space corrects. A key on its own (other than an F-key) is refused, as is the same shortcut for both actions; the keys flash red and the row says why.

**Reset** returns to Fn and Control-Fn.

With two supported layouts, correction is immediate. With more, choose the destination from the small selection window. Correct the text before switching layouts manually. Layout variants such as U.S. and Dvorak are treated separately.

The welcome window can be shown again any time: click the flower in the menu bar, then **Show Welcome Page**.

Keylapse can start when you log in. It can also correct the selection when you click the flower in the menu bar; the menu then opens with a right-click. All of these are in the Keylapse window under **Behavior**. Correction goes through the clipboard; whatever you had copied before is put back afterwards, and clipboard managers are asked not to keep what passes through. Your text stays on your Mac and is not saved by Keylapse.

## Languages

Text correction works with any keyboard layout macOS can describe as a key table, in any language: Keylapse reads each layout's own letters and maps them by physical key position. It needs at least two such layouts. Input sources that compose text, such as Japanese, Chinese or Korean input methods, are labelled **Switching only**: the switch key still cycles through them, and text typed on one of your other layouts can still be corrected while they are active.

Keylapse works out which layout each word of the selected text was typed on from its letters: a layout that cannot type one of them is ruled out. If one layout is left, that is it, whichever layout is active, so you need not switch back first. If several are left (plain Latin letters fit both English and German), it takes the layout the words around it were typed on, then the active layout when that is one of them. When the layouts left would give the same result anyway, because they put those letters on the same keys, it does not matter and the text is corrected; otherwise Keylapse asks you to switch to the layout the text was typed on rather than guess.

Whatever you select is corrected. A sentence typed partly on one layout and partly on another is swapped word by word, so `ghbdsn цщкдв` becomes `привіт world`. With more than one way to correct the selection, a small **Correct to** list asks which; whatever you choose there works. For text from two layouts the first choice swaps them (English ↔ Ukrainian) and each other choice moves the whole text to that layout.

English and Ukrainian have been tested with text replacement in an editor. Other languages still need testing. Letters typed through dead keys cannot always be corrected.

Correction needs an editable field that accepts a paste. Password fields and some editors are not supported.
