# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Promptu.app: a macOS menubar app (~2500 lines of Swift, plus ~600 of tests) that composes LLM
prompts from single-key building blocks, then copies the result to the
clipboard. It is the Mac counterpart to the Emacs package
[promptu.el](https://github.com/mrcnski/promptu.el) and shares its block file.
Single developer, no CI. SwiftPM only — there is no Xcode project.

Requires macOS 14+ and a Swift 6 toolchain.

## Building and verifying

```sh
make test      # swift test — the PromptuCore suite (68 tests)
make run       # swift run, straight from the checkout
make app       # build dist/Promptu.app (ad-hoc signed), regenerating the icon
make install   # copy dist/Promptu.app to /Applications
make zip       # dist/Promptu-<version>.zip, the release artifact
```

`make app` is the real compile check: **treat its `error:` / `warning:` lines as
the source of truth.** Editor/SourceKit diagnostics in this package are noisy —
`No such module 'PromptuCore'` and `Cannot find <symbol> in scope` show up
constantly for code that builds fine, because the module isn't indexed until it
has been built.

Builds are host-arch only. A universal binary needs full Xcode (`swift build
--arch arm64 --arch x86_64`), so releases are Apple Silicon only.

`make icon` rasterizes `mascot.svg` through `scripts/make-icon.swift`; `make
app` runs it, so the icon tracks the SVG automatically.

**Only the pure logic is testable, and only UI-free code can live where the
tests can reach it** — see the target split below. Everything else (popover
behavior, focus, drag, animation, the hotkey) is verified by hand in the GUI,
by the developer, before a commit. Don't guess-fix a GUI symptom: reproduce it,
change one thing, look again.

## Architecture

Two targets, and the split matters:

- **`PromptuCore`** — a plain library: no AppKit, no SwiftUI, no UserDefaults.
  Block model, JSON config, compose/substitute, the composition + undo model,
  reorder math, version comparison. This is the *only* target the test target
  can import.
- **`Promptu`** — an `executableTarget`, so **tests cannot import it**. Status
  item, popover, SwiftUI views, hotkey, settings, update check.

Consequence: new logic worth testing must go in `PromptuCore` — that is why
`Version.isNewer` lives there rather than inside `UpdateChecker`. UI classes are
`@MainActor`.

`main.swift` is a plain AppKit entry point (`NSApplication` + `AppDelegate`)
rather than a SwiftUI `App`: the popover is the whole UI, and even an empty
SwiftUI `Settings` scene would open a stray window on ⌘,. `AppDelegate` is
likewise AppKit rather than `MenuBarExtra`, which has no public API for opening
its window programmatically — the global hotkey needs one.

Key files:

| file | holds |
| --- | --- |
| `Promptu/AppDelegate.swift` | status item, popover lifecycle, hotkey (re)registration, menubar update dot |
| `Promptu/ComposerView.swift` | the main screen: block grid, live preview, key handling, footer hints (largest file) |
| `Promptu/Session.swift` | all UI state; wraps `Composition`, owns the block **pages** and writes them back to disk |
| `Promptu/HotKey.swift` | Carbon `RegisterEventHotKey` wrapper + the persisted `HotKeySpec` |
| `Promptu/Theme.swift` | Catppuccin Latte (light) / Nimbus (dark) palettes |
| `Promptu/Motion.swift` | the one gate for every animation (`Motion.gated`) |
| `PromptuCore/Composition.swift` | entries, point, undo/redo — the model under `Session` |

### Popover and hotkey gotchas

These are load-bearing and easy to reintroduce:

- The popover's `NSHostingController` uses `sizingOptions = .preferredContentSize`,
  so the window resize trails the SwiftUI content by a frame. **Anything that
  changes the panel's height while it is open flashes the whole app.** That is
  why a freshly-found update never pops its banner mid-view (see
  `UpdateChecker.panelIsOpen`).
- With animations off, `popover.animates` is `false`, and `performClose` then
  fires `popoverDidClose` *synchronously, inside the hotkey's own Carbon event
  dispatch*. Re-registering the hotkey there calls `RemoveEventHandler` on the
  handler that is still executing and kills the hotkey after one use. Work
  scheduled from `popoverDidClose` must stay deferred to the next runloop turn.
- `open()` forces activation with the deprecated
  `NSApp.activate(ignoringOtherApps:)`. Cooperative `NSApp.activate()` is denied
  to an accessory app, leaving the previous app frontmost under the popover.
  Despite the deprecation notice, the forced call is the one that works
  (verified on macOS 15.7).
- Editing shortcuts (⌘C/⌘V/⌘A/undo) only work because `installEditMenu()`
  builds a never-shown main menu; an accessory app starts with none.
- `toggle()` treats a shown-but-invisible popover as closed, to recover from a
  wedge seen in the wild.

### Config files

Blocks live in `~/.config/promptu/*.json`. `blocks.json` is page one; every
other `.json` in that directory is another page, cycled with ←/→. The schema is
shared with Emacs promptu (`promptu-blocks-from-json`), so **any change to it
has to land in both repos**:

```json
{ "key": "i", "desc": "investigate", "text": "investigate {link}", "placeholders": ["link"] }
```

`BlocksConfig.serialize` hand-rolls the JSON (one block per line, fields in
schema order) so a file the app saves still reads like a hand-written one and
diffs cleanly. A test pins that serializing the default blocks reproduces
`defaultBlocksJSON` byte for byte — keep it that way.

Seeding rules differ on purpose: `blocks.json` is seeded whenever it is missing
(`loadOrSeed`, mirroring promptu.el), while the bundled preset pages are seeded
**once**, behind the `presetsSeeded` UserDefaults flag, so deleting a preset
page keeps it deleted. An existing file is never overwritten; a malformed one
throws instead of being clobbered.

UserDefaults keys in use: `hotKeyCode` / `hotKeyModifiers` / `hotKeyDisplay`,
`theme`, `disableAnimations`, `pageIndex`, `presetsSeeded`, `loginItemApplied`,
`updateCheckDisabled`, `updateLastCheck`, `updateLatestVersion`,
`updateLatestURL`, `updateDismissedVersion`. Bundle id is
`ski.mrcn.promptu-app`; `defaults read ski.mrcn.promptu-app` is the quickest way
to see live state.

## Releasing

1. `make test`, then verify the build by hand in the GUI.
2. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`;
   commit as `chore: release X.Y.Z`.
3. `make zip`, then `shasum -a 256 dist/Promptu-X.Y.Z.zip`.
4. Tag `vX.Y.Z`, push `main` and the tag, `gh release create` with the zip
   attached and notes in the established shape (title, New / Fixes, Install
   with the quarantine note, SHA-256).
5. Bump `version` + `sha256` in
   `~/Sync/Repos/github.com/mrcnski/homebrew-tap/Casks/promptu.rb` and push.
6. Re-download the uploaded asset and confirm its SHA matches the cask.

There is no CHANGELOG; the GitHub release body is the changelog.

## Conventions

- Swift API docs use `///`, in full sentences, and explain **why** — most
  comments in this codebase record a constraint that was learned the hard way,
  not what the line does. Preserve them; if you remove a workaround, remove its
  comment with it and say why in the commit.
- Commit subjects are conventional-commit style, lowercase, imperative
  (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`). The body explains the
  reasoning, not the diff. Trailer: `Co-Authored-By: Claude <model> <noreply@anthropic.com>`.
- Logically distinct changes go in separate commits, even when they were
  developed together.
- Tests use Swift Testing (`@Test` / `#expect`), one file per `PromptuCore`
  type, with comments naming the bug each non-obvious case guards against.
- `notes.md` at the repo root is an untracked scratch file for pending ideas —
  read it for context, but it is not part of the app.
