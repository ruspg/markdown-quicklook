# markdown-quicklook

Quick Look preview for Markdown files on macOS. Press Space on any `.md` file in Finder to see rendered Markdown instead of plain text.

## Why

Markdown is everywhere — Obsidian vaults, AI-generated docs, GitHub READMEs, dev notes. Yet macOS shows `.md` files as plain text in Quick Look. This project fixes that.

## What's included

- **PreviewMarkdown** — Quick Look extension that renders Markdown with syntax highlighting, YAML front matter support, and configurable fonts/colors. Built from [smittytone/PreviewMarkdown](https://github.com/smittytone/PreviewMarkdown) with patches for local builds.
- **QLToggle** — lightweight menu bar utility to switch between rendered and plain text Quick Look modes.

## Requirements

- macOS 13+
- Xcode 16+ (or Command Line Tools with `xcodebuild`)

## Install

```bash
git clone --recursive https://github.com/ruspg/markdown-quicklook.git
cd markdown-quicklook
./build.sh
```

The script builds both apps, installs them to `~/Applications/`, registers the Quick Look extensions, and launches everything. No sudo required.

## QLToggle

A menu bar icon appears after install:

- **Filled icon** — Markdown rendering is active
- **Outline icon** — Quick Look shows plain text
- Click to toggle between modes or open PreviewMarkdown settings

> After toggling, close and reopen Quick Look (press Space twice) on the file to see the change.

## Updating

After a macOS or Xcode update, re-run:

```bash
cd markdown-quicklook
git submodule update --remote
./build.sh
```

## How it works

[PreviewMarkdown](https://github.com/smittytone/PreviewMarkdown) is a source-available macOS app by [@smittytone](https://github.com/smittytone) that provides Quick Look preview and thumbnail extensions for Markdown files. The author sells it on the [App Store](https://apps.apple.com/app/previewmarkdown/id1492280469) and intentionally omits certain files from the repo (feedback endpoint, Team ID, assets).

This project provides:
- Minimal stubs for the missing files
- A build script that patches paths, bundle identifiers, code signing, and entitlements for local (ad-hoc signed) builds
- QLToggle — an original utility to enable/disable the extension from the menu bar

## Uninstall

```bash
rm -rf ~/Applications/PreviewMarkdown.app ~/Applications/QLToggle.app
qlmanage -r
```

## License

QLToggle and build scripts: [MIT](LICENSE)

PreviewMarkdown: see [smittytone/PreviewMarkdown license](https://github.com/smittytone/PreviewMarkdown/blob/main/LICENSE.md)
