# AGENTS.md — markdown-quicklook

One-command rendered Markdown for macOS Quick Look: a semantic patch layer and
build wrapper around the PreviewMarkdown submodule, a menu bar toggle, and a
no-Xcode release installer.

## Layout

- `build.sh` — patch, verify (74 outcome assertions), build, install.
  `--check` = patch + verify only, restores the submodule.
  `--release-zip` = build + package `release/` artifacts, no install.
- `patches/` — the patch layer (seds + generated stubs), applied to a pristine
  submodule checkout, never committed to the submodule.
- `PreviewMarkdown/` — submodule of [smittytone/PreviewMarkdown](https://github.com/smittytone/PreviewMarkdown);
  `build.sh` resets it to pristine before patching.
- `QLToggle/` — menu bar toggle, compiled directly with `swiftc` (no Xcode project).
- `install.sh` — POSIX sh installer for `curl | bash`; downloads the release zip,
  needs no Xcode, verifies against `SHA256SUMS` when the release publishes one.
- `test.sh` — tests the installed product; `--quick` = bundle checks only.

## Commands

- Build + install locally: `./build.sh` — requires a **full Xcode** (`xcodebuild`
  refuses to run against Command Line Tools only; this bit a contributor before).
- Pre-flight without building: `./build.sh --check`
- Test the installed product: `./test.sh` / `./test.sh --quick`
- Install/upgrade from releases, no Xcode: `./install.sh [version]`

## Release process

1. Tag the release, then `./build.sh --release-zip` (needs full Xcode).
2. Artifacts land in `release/` (gitignored): the zip + `SHA256SUMS`.
3. Upload **both** files as release assets — `install.sh` verifies the zip
   against `SHA256SUMS` when present, and prints an unverified hash when not.
4. Release notes lead with the curl one-liner from the README; the manual zip
   extraction dance is the fallback, not the headline.

## Release zip contract (install.sh depends on every line)

- Zip contains a single folder `markdown-quicklook/` holding exactly
  `PreviewMarkdown.app` and `QLToggle.app`.
- Asset name: `markdown-quicklook-<tag>-macos-universal.zip`.
- Checksum file: `SHA256SUMS`, standard `<sha256>  <filename>` lines.
- Changing any of the above means updating `install.sh` in the same release.
