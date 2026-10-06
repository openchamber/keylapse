# Building, checking and seeing Keylapse

Everything here runs from the repository root. `bun kl-dev` is the menu; the same commands work with `node scripts/kl-dev.mjs`. No dependencies are installed for it.

## The everyday loop

| Command | What it does | Who it is for |
| --- | --- | --- |
| `bun kl-dev preview` | Debug build, then the window rendered to PNGs in `dist/previews`: `settings`, `settings-before-setup`, `welcome-before-setup`, `welcome-ready`, `welcome-corrected`. Prints each path with a PASS/FAIL line. Add any `--preview-…` flag (below) to render one state instead, into `custom.png`. | Agents: this is how you look at the UI. |
| `bun kl-dev install` | Release build, signed with the local certificate, quit the running copy, copy into /Applications, open. | Both. The user expects it after every change. |
| `bun kl-dev build` | Release build only: `dist/Keylapse.app` and `dist/Keylapse.zip`. | Both. |
| `bun kl-dev package` | Writes `~/Desktop/Keylapse-<version>.zip` for a tester: a folder with `Keylapse.app` and `Keylapse Reset.command` (`scripts/Keylapse Reset.command`: quits Keylapse, takes back its two permissions and forgets its settings, without opening it again; double-click, no repository needed). Signed with the local certificate, so macOS blocks the first open of each: after trying once, allow it in System Settings → Privacy & Security → Open Anyway. Builds first if needed. | The user. Say the path. |
| `bun kl-dev watch` | Debug build relaunched on every saved `.swift` file, about a second each. The debug binary has no bundle, so macOS gives it no permissions: the window can be checked, the shortcuts cannot. Quits the installed copy while it runs. | The user. Useless for an agent, which cannot see the window. |
| `bun kl-dev reset` | Back to before the first launch: quits Keylapse, `tccutil reset` for Accessibility and Input Monitoring, `defaults delete com.openchamber.keylapse`, then opens the installed app so the first launch is on screen. The app stays installed; Launch at login stays with macOS. | The user. **Agents: never without being asked**, it revokes the user's permissions. For the first-launch look use the welcome previews. |

Unit tests: `bash scripts/test.sh` (Swift Testing). To install by hand: quit Keylapse, copy the bundle to `/Applications` with `ditto`, open it.

Releases: push an annotated tag `v<version>` matching `CFBundleShortVersionString` in `Resources/Info.plist` (`git tag -a v0.2.0 -m "What is new"`; the message becomes the release notes and what the in-app update window shows); the Release workflow on GitHub builds a universal binary (`UNIVERSAL=1 bash scripts/build.sh`, which needs full Xcode, so it does not run with the Command Line Tools alone), signs with the Developer ID certificate, notarises, writes the Sparkle `appcast.xml` and publishes both with `Keylapse-<version>.zip` (details in HANDOFF.md under Environment). The first build on a machine needs the network once, for `swift package resolve` to fetch Sparkle. A local notarised build needs `SIGNING_IDENTITY` set to the Developer ID certificate and either `NOTARY_PROFILE` or `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID` in the environment of `bash scripts/build.sh`.

## What an agent can and cannot verify here

- No Screen Recording for a terminal process and no assistive access for `osascript`, so screenshots and UI scripting fail. Use `preview`.
- A process started from a terminal does not inherit the app's permissions. Checks that need the event tap, Accessibility or the clipboard must run through LaunchServices: `open -a /Applications/Keylapse.app --args <flag> <path>`, then read the report file. They still need the permissions granted to the app; when they are not, report what stayed unverified rather than working around it.
- The welcome page's Try it correction is such a check (`--check-welcome-demo`), so is `--check-selection <report>`, which corrects the selection of a focused TextEdit document as the shortcut would.
- `preview` renders off screen and does not touch the installed Keylapse, which keeps running. The window is rendered inactive: prominent buttons look grey and selections dark. That is the renderer, not a bug.

## Diagnostics flags

All are handled in `Sources/Keylapse/Diagnostics.swift`; its header comment is the authoritative list. The ones used most:

- `--check-settings <png> [state flags]` renders the window. `preview` wraps it. State flags: `--preview-welcome`, `--preview-settings-page`, `--preview-setup-ready`, `--preview-missing-permissions`, `--preview-fn-conflict`, `--preview-fn-unknown`, `--preview-demo-done`, `--preview-waiting`, `--preview-waiting-fn`, `--preview-pulse` (the beat's bright half), `--preview-many-layouts`, `--preview-rows <n>`, `--preview-scrolled-to-end`, `--preview-switch-key <name>`, `--preview-combo-shortcut`, `--preview-recording` (with `--preview-recording-held` for Control and Option held), `--preview-recording-switch`, `--preview-refused`, `--preview-destinations`.
- `--check-welcome-demo <report> [--preview-setup-ready]` selects the welcome word and runs the real correction on it.
- `--check-menu-icon <png>` writes the paused menu bar flower at 2×; works from a terminal.
- `--check-permission-hint <report>` opens the Accessibility pane, shows the floating hint and reports both windows' positions as macOS lists them; works from a terminal, prompts for nothing.
- `--check-fn-menu <report>` opens Keyboard settings and lists the labels and pop-up menus Keylapse can read there, with PASS and a TARGET line when it finds the Press 🌐 key to menu the floating hint points at. Needs Accessibility, so run it through LaunchServices with Keylapse quit first.
- `--self-test`, `--check-layouts`, `--check-discovery`, `--check-cycle`, `--source-report` check the layout tables against the installed input sources; none change system settings.
- `--permission-report <path>` writes the permission and login-item state.

## Seeing the welcome page again

`bun kl-dev reset`, or just `defaults delete com.openchamber.keylapse onboarded` to keep the permissions.

## The first launch, by hand

What a person should see at each step; the previews cannot show the parts that involve macOS.

1. `bun kl-dev reset` (it opens Keylapse again by itself): the welcome page, only Grant… beside Accessibility prominent and breathing, pause bars in the menu bar flower.
2. Grant…: the row shows the Keylapse switch replica, macOS shows its Accessibility dialog (the pane does not open by itself).
3. Open System Settings in that dialog: Keylapse steps aside, the hint sits on the bottom edge of System Settings.
4. Turn Keylapse on there: System Settings closes, two checkmarks (Input Monitoring follows Accessibility), the switch-key step becomes current with Use other keys and Open Settings.
5. Either Open Settings and choose Do Nothing for Press 🌐 key to, or Use other keys and press a key or combination for switching, then one for correcting. Third checkmark, the menu bar flower gets its dot back.
6. The Try it keycaps breathe and the word is selected: Control + Fn, choose English in Correct to if asked, the word becomes hello with Fixed. ⌘Z undoes it.
7. Start using Keylapse is now the prominent button; it shows the settings page. The flower menu has Pause and Show Welcome Page.
8. In another app (Notes, then an Electron app): type ghbdsn, select it, Control + Fn. It becomes привіт, the layout switches to Ukrainian, ⌘Z brings ghbdsn back, and whatever was on the clipboard before is still there.
