# markdown-quicklook

Quick Look preview for Markdown files on macOS. Press Space on any `.md` file in Finder to see rendered Markdown instead of plain text.

![macOS default vs markdown-quicklook](assets/comparison.png)

![Light and dark previews](assets/light-dark.png)

> Both images above are rendered by this project's actual rendering engine (via a local harness), including syntax-coloured code.

## Why

Markdown is everywhere — Obsidian vaults, AI-generated docs, GitHub READMEs, dev notes. Yet macOS shows `.md` files as plain text in Quick Look. This project fixes that, with a GitHub-compact look: Helvetica Neue body text with true bold, Menlo code, automatic light/dark pages (`#0D1117` night mode), and YAML front-matter preview.

## What's included

- **PreviewMarkdown** — Quick Look preview and thumbnail extensions that render Markdown. Built from [smittytone/PreviewMarkdown](https://github.com/smittytone/PreviewMarkdown) with a self-verifying patch layer for local (ad-hoc signed) builds.
- **QLToggle** — a universal (arm64 + x86_64) menu bar utility to switch between rendered and plain-text Quick Look, with launch-at-login, per-extension status lines, and a Restart Quick Look action.

## Requirements

- macOS 13+ on Apple Silicon or Intel
- Xcode with command line tools (`xcode-select --install` may be enough; developed on Xcode 26)
- Network access on first build (Swift Package dependencies resolve from branches)

## Install

```bash
git clone --recursive https://github.com/ruspg/markdown-quicklook.git
cd markdown-quicklook
./build.sh
```

The script resets the submodule to pristine, applies patches, **verifies every patch by outcome** (it refuses to build if upstream drifted), builds both apps, ad-hoc signs, installs to `~/Applications/`, registers the extensions, and relaunches Quick Look. No sudo required.

Useful companions:

```bash
./build.sh --check        # patch + verify only: safe pre-flight for a submodule bump
./reset-settings.sh       # one-time reset of preview settings (e.g. after a theme change)
./test.sh                 # test the installed product (bundle checks + render checks)
./test.sh --quick         # bundle checks only
```

## QLToggle

A menu bar icon appears after install:

- **Filled icon** — Markdown rendering is active; **outline icon** — plain text
- Click to toggle both extensions (Previewer + Thumbnailer) at once
- Status lines show each extension's live state
- **Launch at Login** (uses `SMAppService`; errors are surfaced in the menu)
- **Restart Quick Look** resets the Quick Look cache if previews ever go stale
- **PreviewMarkdown Settings…** opens the host app by bundle ID

> After toggling, close and reopen Quick Look (press Space twice) to see the change.

## Updating

After a macOS/Xcode update, or to pick up a new upstream PreviewMarkdown release:

```bash
cd markdown-quicklook
git submodule update --remote
./build.sh --check    # confirm every patch still applies and verifies
./build.sh
```

If `--check` fails, upstream has drifted: the failed assertions tell you exactly which rewrite stopped matching. The build refuses to continue in that case rather than shipping a silently wrong binary.

## Known limitations

- **Syntax highlighting renders plain inside Quick Look** in these local builds — the highlighter (JavaScriptCore) fails at runtime inside the sandboxed extension host, proven unrelated to entitlements by A/B testing. The `github`/`github-dark` code themes are wired and will activate once the runtime issue is solved (tracking in issues).
- **Thumbnails** use a separate, fixed-size pipeline and can look plainer than the preview; the `qlmanage` thumbnail channel is also flaky for testing (hence `test.sh` treats renders as best-effort).

## Uninstall

```bash
# 1. Disable Launch at Login in the QLToggle menu (or System Settings → Login Items)
rm -rf ~/Applications/PreviewMarkdown.app ~/Applications/QLToggle.app
rm -rf ~/Library/Group\ Containers/com.local.suite.previewmarkdown
rm -f  ~/Library/Preferences/com.local.suite.previewmarkdown.plist
qlmanage -r
```

## How it works

[PreviewMarkdown](https://github.com/smittytone/PreviewMarkdown) is a source-available macOS app by [@smittytone](https://github.com/smittytone) that provides Quick Look preview and thumbnail extensions for Markdown files. The author sells it on the [App Store](https://apps.apple.com/app/previewmarkdown/id1492280469) and intentionally omits certain files from the repo (feedback endpoint, Team ID, assets).

This project provides:

- Minimal stubs for the missing files
- A patch layer that rewrites paths, bundle identifiers, code signing, entitlements, fonts, colours, and spacing for local ad-hoc builds — with a 30+-assertion verification gate
- A wrapper default theme ("GitHub Compact") applied entirely through the patch layer
- QLToggle, an original menu bar utility

## License

QLToggle, build/test scripts, and the patch layer: [MIT](LICENSE)

PreviewMarkdown: see the [smittytone/PreviewMarkdown license](https://github.com/smittytone/PreviewMarkdown/blob/main/LICENSE.md)
