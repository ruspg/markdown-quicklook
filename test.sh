#!/bin/bash
set -euo pipefail

# markdown-quicklook local test script (wayfinder #13).
#
# Complements build.sh's patch-verification gate: this checks the BUILT and
# INSTALLED product. Hard failures = the build is wrong. Warnings = channels
# known to be flaky (qlmanage thumbnails) or items needing human eyes.
#
#   ./test.sh          run everything
#   ./test.sh --quick  bundle checks only (no renders)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PM_DIR="$SCRIPT_DIR/PreviewMarkdown"
APP="$HOME/Applications/PreviewMarkdown.app"
TMP="$(mktemp -d /tmp/qltest.XXXXXX)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0
ok()   { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
bad()  { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; WARN=$((WARN+1)); }

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

# --- Bundle checks (hard) ---

expected_ver="$(git -C "$PM_DIR" describe --tags --abbrev=0 2>/dev/null || git -C "$PM_DIR" rev-parse --short HEAD)"
installed_ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[ -n "$installed_ver" ] && [ "$installed_ver" = "$expected_ver" ] \
    && ok "installed app version $installed_ver == submodule $expected_ver" \
    || bad "version mismatch: installed='$installed_ver' submodule='$expected_ver'"

for appex in "Markdown Previewer" "Markdown Thumbnailer"; do
    bundle="$APP/Contents/PlugIns/$appex.appex"
    sig="$(codesign -dv "$bundle" 2>&1 || true)"
    if [ -d "$bundle" ] && [[ "$sig" == *adhoc* ]]; then
        ok "$appex present, ad-hoc signed"
    else
        bad "$appex missing or not ad-hoc signed"
    fi
done

lipo -info "$APP/Contents/PlugIns/Markdown Previewer.appex/Contents/MacOS/Markdown Previewer" 2>/dev/null | grep -q "x86_64" \
    && ok "Previewer binary universal (arm64+x86_64)" \
    || warn "Previewer not universal (lipo)"

if pluginkit -m -p com.apple.quicklook.preview 2>/dev/null | grep -q '^+.*com\.local\.PreviewMarkdown\.Previewer'; then
    ok "Previewer registered and active (pluginkit '+')"
else
    bad "Previewer not listed as active by pluginkit"
fi

# --- Settings-suite canary (hard: plumbing; appearance needs eyes) ---

SUITE_PLIST="$HOME/Library/Group Containers/com.local.suite.previewmarkdown/Library/Preferences/com.local.suite.previewmarkdown.plist"
if [ -f "$SUITE_PLIST" ]; then
    ls_seed="$(/usr/libexec/PlistBuddy -c 'Print :com-bps-previewmarkdown-line-spacing' "$SUITE_PLIST" 2>/dev/null || true)"
    case "$ls_seed" in
        1.1*) ok "suite line-spacing seeded sane ($ls_seed)" ;;
        "")   warn "suite exists but line-spacing unseeded (floor guard now covers this)" ;;
        *)    warn "suite line-spacing is '$ls_seed' (expected 1.1) — check re-seeding" ;;
    esac
else
    warn "suite plist absent — defaults re-seed on next preview; line-spacing floor now protects fresh states"
fi

# --- Fixture renders (best-effort: qlmanage thumbnail channel is flaky) ---

analyze() {  # analyze <png> <min_opaque>
    python3 - "$1" "$2" <<'PYEOF'
import struct, sys, zlib
path, min_opaque = sys.argv[1], int(sys.argv[2])
try:
    data = open(path, 'rb').read()
except FileNotFoundError:
    print("missing"); sys.exit(2)
pos = 8; idat = b''; w = h = 0
while pos < len(data):
    ln = struct.unpack('>I', data[pos:pos+4])[0]; typ = data[pos+4:pos+8]
    if typ == b'IHDR': w, h = struct.unpack('>II', data[pos+8:pos+16])
    if typ == b'IDAT': idat += data[pos+8:pos+8+ln]
    pos += 12 + ln
raw = zlib.decompress(idat); stride = w*4
opaque = 0; old_palette = 0
for y in range(0, h, 3):
    for x in range(0, w, 3):
        o = y*(stride+1)+1+x*4
        r, g, b, a = raw[o], raw[o+1], raw[o+2], raw[o+3]
        if a > 100:
            opaque += 1
            # old theme: magenta 148,23,81 or pure green 0,255,0
            if (abs(r-148)<25 and abs(g-23)<25 and abs(b-81)<25) or (r<60 and g>220 and b<60):
                old_palette += 1
print(f"{opaque} {old_palette}")
PYEOF
}

if [ "$QUICK" -eq 0 ]; then
    stamp="$(date +%s)"
    cat > "$TMP/fixture.md" <<EOF
# Fixture $stamp

Body with **bold**, *italic*, \`inline code\`, a [link](https://github.com/ruspg/markdown-quicklook).

\`\`\`swift
func greet(_ name: String) -> Int {
    let count = 42
    return count
}
\`\`\`

> A quote.

| A | B |
|---|---|
| 1 | 2 |
EOF
    qlmanage -t -s 1200 -o "$TMP" "$TMP/fixture.md" >/dev/null 2>&1 || true
    if [ -f "$TMP/fixture.md.png" ]; then
        read -r opaque old_palette <<< "$(analyze "$TMP/fixture.md.png" 200)"
        if [ "${opaque:-0}" -ge 200 ]; then
            ok "fixture render non-empty ($opaque opaque px)"
            if [ "${old_palette:-0}" -gt 0 ]; then
                bad "old magenta/green palette colours present in render ($old_palette px)"
            else
                ok "no old-palette colours in render"
            fi
        else
            warn "fixture render near-empty ($opaque px) — qlmanage thumbnail channel known-flaky; check a Finder Space-press"
        fi
    else
        warn "no fixture render produced — qlmanage thumbnail channel known-flaky"
    fi

    echo ""
    echo "Manual checklist (2 min, needs your eyes):"
    echo "  1. Space-press a .md in Finder: dark #0D1117 page, bold text bold, code on dark panels, emoji correct"
    echo "  2. Change a setting in the PreviewMarkdown app; Space-press again — preview honours it"
    echo "  3. QLToggle menu: status lines correct, toggle works, login item registers"
    echo "  4. Finder icon preview of a .md: readable (thumbnail channel)"
fi

# --- Summary ---

echo ""
echo "=== $PASS passed, $FAIL failed, $WARN warned ==="
[ "$FAIL" -eq 0 ] || exit 1
rm -rf "$TMP"
