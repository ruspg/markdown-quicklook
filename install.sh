#!/bin/sh
# markdown-quicklook installer: downloads the latest release and installs both
# Quick Look apps to ~/Applications. No Xcode, no git, no developer account.
#
#   curl -fsSL https://raw.githubusercontent.com/ruspg/markdown-quicklook/main/install.sh | bash
#
# Pin a version by appending:  ... | bash -s -- v2.1.0
set -eu

REPO="ruspg/markdown-quicklook"
APPS_DIR="$HOME/Applications"

say()  { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "this installer is macOS-only"
[ "$(id -u)" -ne 0 ] || fail "do not run with sudo — apps install into your home directory"
command -v curl  >/dev/null 2>&1 || fail "curl not found"
command -v ditto >/dev/null 2>&1 || fail "ditto not found"

macver=$(sw_vers -productVersion)
macmajor=${macver%%.*}
[ "$macmajor" -ge 13 ] || fail "macOS 13 or later required (found $macver)"

VERSION=${1:-}
if [ -n "$VERSION" ]; then
    case "$VERSION" in
        v*) : ;;
        *) VERSION="v$VERSION" ;;
    esac
    asset_url="https://github.com/$REPO/releases/download/$VERSION/markdown-quicklook-$VERSION-macos-universal.zip"
else
    say "Resolving latest release..."
    asset_url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*"' \
        | sed 's/.*"\(https[^"]*\)".*/\1/' \
        | grep -- '-macos-universal\.zip$' \
        | head -1) || true
fi
[ -n "${asset_url:-}" ] || fail "could not resolve a release asset (network error or API rate limit — retry in a minute)"

say "Downloading $asset_url"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/markdown-quicklook.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
curl -fsSL --retry 3 -o "$tmp/release.zip" "$asset_url" || fail "download failed"
say "sha256: $(shasum -a 256 "$tmp/release.zip" | awk '{print $1}')"

ditto -x -k "$tmp/release.zip" "$tmp" || fail "archive could not be extracted"
[ -d "$tmp/markdown-quicklook/PreviewMarkdown.app" ] && [ -d "$tmp/markdown-quicklook/QLToggle.app" ] \
    || fail "unexpected archive layout"

say "Stopping running instances..."
killall PreviewMarkdown QLToggle 2>/dev/null || true

mkdir -p "$APPS_DIR"
for app in PreviewMarkdown QLToggle; do
    rm -rf "$APPS_DIR/$app.app"
    mv "$tmp/markdown-quicklook/$app.app" "$APPS_DIR/$app.app"
done

xattr -dr com.apple.quarantine "$APPS_DIR/PreviewMarkdown.app" "$APPS_DIR/QLToggle.app" 2>/dev/null || true

say "Launching and restarting Quick Look..."
open "$APPS_DIR/PreviewMarkdown.app"
open "$APPS_DIR/QLToggle.app"
qlmanage -r >/dev/null 2>&1 || true

say ""
say "Installed to $APPS_DIR. Press Space on a .md file in Finder to preview it."
say "If a stale preview appears, press Space twice — Quick Look caches the previous renderer."
say "QLToggle sits in the menu bar: filled icon = Markdown rendering on, outline = plain text."
