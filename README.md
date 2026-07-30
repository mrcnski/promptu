<div align="center">
  <img src="mascot.svg" alt="promptu mascot — a friendly creature built from stacked terminal blocks" width="180"/>

# promptu

Compose LLM prompts from building blocks, right from the menubar!

*The opposite of 'impromptu': composed, not off-the-cuff.*

<img src="screenshot.png" alt="promptu menu showing blocks, controls, and a live preview" width="365">
</div>

## Usage

Press `⌥⌘P` (the default hotkey) from any app, or click the menubar icon,
to open promptu.

Press block keys to build the prompt while watching the live preview, then press
`RET`.  The composed prompt lands on the clipboard and focus returns to where
you were, ready to paste.

The panel follows the system appearance by default: [Catppuccin
Latte](https://catppuccin.com) in light mode,
[Nimbus](https://github.com/mrcnski/nimbus-theme) in dark mode.

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask mrcnski/tap/promptu
```

Or download `Promptu-<version>.zip` from
[Releases](https://github.com/mrcnski/promptu/releases), unzip, and
drag Promptu.app into /Applications.

Either way, the app is ad-hoc signed and not notarized, so macOS
quarantines the download; clear the flag once:

```sh
xattr -d com.apple.quarantine /Applications/Promptu.app
```

Or build from source (below). Locally built apps don't need the quarantine cleared.

## Blocks

Blocks are customizable and are stored in `~/.config/promptu/blocks.json`.  On
first launch, when the file doesn't exist, it is seeded with promptu's default
block set.  The file is an array of objects:

```json
[
  { "key": "r", "desc": "review", "text": "review your changes" },
  { "key": "i", "desc": "investigate", "text": "investigate {link}", "placeholders": ["link"] },
  { "key": "P", "desc": "push", "text": "push when done", "negative": "don't push" }
]
```

`{name}` placeholders are prompted for when the block is added.  Blocks are
re-read on app restart.

Blocks can also be edited in-app: `⌘B` opens the Block Editor.  Click a block to
change or delete it, or add a new one.

### Presets

`←`/`→` cycle between pages of blocks: `blocks.json` plus every other `.json`
file in `~/.config/promptu/`, one page per file.  The Block Editor edits
whichever page is showing.

Some preset pages are bundled: `understand`, `build`, `ship`, `fix`.  These are
adapted from the [Claude Code prompt
library](https://code.claude.com/docs/en/prompt-library).  They are seeded once
on first launch; delete a file to drop its page (it stays gone), or add your own
`.json` to gain one.

## History

By default, every prompt you copy is stored so you can reuse it again later.
`⌘Y` opens the history view.

A recalled prompt acts like a real composition again and its entries can be
removed, reordered, and edited.

**Note:** The last 50 prompts are kept on your Mac, in plain text, including
whatever you typed into placeholders.  Settings has a "remember prompts" switch
("off" stops recording, but anything already stored stays until cleared in
settings or the history view).

## Build

```sh
make test      # run the core tests
make run       # run from the checkout
make dev       # auto-rebuild and relaunch on save (brew install watchexec)
make app       # build dist/Promptu.app (ad-hoc signed)
make install   # copy it to /Applications
```

Requires macOS 14+ and a Swift 6 toolchain (Xcode 16+).

Launch with `open dist/Promptu.app` from the checkout, or, once `make install`
has run, launch "Promptu" from Spotlight or /Applications.

Apps run from the checkout skip the automatic login-item registration; use the
settings toggle if you want one.

## Todo

- Custom separator / negation prefix (fixed at `"\n- "` / `"don't "`)
- Universal (Intel + Apple Silicon) release binaries — needs full Xcode
  for `swift build --arch arm64 --arch x86_64`; releases are currently
  Apple Silicon only

## See also

- The original [Emacs package](https://github.com/mrcnski/promptu.el) that
  started it all!

## License

GPL-3.0, like promptu.
