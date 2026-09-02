#!/bin/sh
# markdown-quicklook installer: downloads the latest release and installs both
# Quick Look apps to ~/Applications. No Xcode, no git, no developer account.
#
#   curl -fsSL https://raw.githubusercontent.com/ruspg/markdown-quicklook/main/install.sh | bash
#
# Pin a version by appending:  ... | bash -s -- v2.1.0
set -eu

PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

REPO="ruspg/markdown-quicklook"
APPS_DIR="$HOME/Applications"
APPS="PreviewMarkdown QLToggle"

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
else
    say "Resolving latest release..."
    latest_url=$(curl -fsSL --max-time 30 -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest") \
        || fail "could not reach GitHub to resolve the latest release (network error)"
    case "$latest_url" in
        */releases/tag/*) : ;;
        *) fail "could not determine the latest release tag (unexpected redirect: $latest_url)" ;;
    esac
    VERSION=${latest_url##*/}
    say "Latest release is $VERSION"
fi
asset_url="https://github.com/$REPO/releases/download/$VERSION/markdown-quicklook-$VERSION-macos-universal.zip"

say "Downloading $asset_url"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/markdown-quicklook.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
curl -fsSL --retry 3 --connect-timeout 10 --max-time 300 -o "$tmp/release.zip" "$asset_url" \
    || fail "download failed"
say "sha256: $(shasum -a 256 "$tmp/release.zip" | awk '{print $1}')"

ditto -x -k "$tmp/release.zip" "$tmp" || fail "archive could not be extracted"

for app in $APPS; do
    [ -d "$tmp/markdown-quicklook/$app.app" ] || fail "archive is missing $app.app — unexpected layout"
    codesign --verify --deep --strict "$tmp/markdown-quicklook/$app.app" 2>/dev/null \
        || fail "$app.app failed signature validation — the archive is corrupt; the installed version was not touched"
done

say "Stopping running instances..."
killall $APPS 2>/dev/null || true

mkdir -p "$APPS_DIR"
for app in $APPS; do
    rm -rf "$APPS_DIR/.$app.previous"
    if [ -d "$APPS_DIR/$app.app" ]; then
        mv "$APPS_DIR/$app.app" "$APPS_DIR/.$app.previous" || fail "could not move the installed $app.app aside"
    fi
    if mv "$tmp/markdown-quicklook/$app.app" "$APPS_DIR/$app.app"; then
        rm -rf "$APPS_DIR/.$app.previous"
    elif [ -d "$APPS_DIR/.$app.previous" ]; then
        mv "$APPS_DIR/.$app.previous" "$APPS_DIR/$app.app"
        fail "could not install $app.app — previous install restored"
    else
        fail "could not install $app.app"
    fi
done

for app in $APPS; do
    xattr -dr com.apple.quarantine "$APPS_DIR/$app.app" 2>/dev/null || true
done

say "Launching and restarting Quick Look..."
open "$APPS_DIR/PreviewMarkdown.app" || say "warning: could not launch PreviewMarkdown"
open "$APPS_DIR/QLToggle.app"       || say "warning: could not launch QLToggle"
qlmanage -r >/dev/null 2>&1 || true

say ""
say "Installed to $APPS_DIR. Press Space on a .md file in Finder to preview it."
say "If a stale preview appears, press Space twice — Quick Look caches the previous renderer."
say "QLToggle sits in the menu bar: filled icon = Markdown rendering on, outline = plain text."
