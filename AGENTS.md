# Keylapse

A macOS menu bar app in Swift: switches keyboard layouts and fixes text typed in the wrong one.

- Read `HANDOFF.md` first (environment, decisions, state of the UI, plans). Before touching the window, read `DESIGN.md` too; both are authoritative and are updated with every change.
- How to build, check and look at the app, and what you cannot verify from a terminal, is in `TOOLING.md`. `bun kl-dev reset` revokes the user's permissions; never run it unasked.
- The documents describe the current state, not history. When a change touches something they already say (a command, a rule, a decision, how a screen looks or behaves), update that passage in the same step, in the same commit: README.md for what the user sees, DESIGN.md for the window, HANDOFF.md for decisions and plans, TOOLING.md for the build and check commands. Replace the old text; do not add a note beside it.
- Commit locally after each finished step; push only when asked.
