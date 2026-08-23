#!/bin/bash
set -euo pipefail

# markdown-quicklook build script (hardened).
#
#   ./build.sh          patch, verify, build, install, register, launch
#   ./build.sh --check  patch + verify only — no build, no install, no launch;
#                       the submodule is restored to pristine afterwards.
#
# The patch layer is semantic (seds + regenerated stubs) applied to a CLEAN
# submodule, then verified by OUTCOME assertions. If upstream drifts so a sed
# no longer lands, verification fails loudly instead of shipping a wrong build.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PM_DIR="$SCRIPT_DIR/PreviewMarkdown"
PATCHES_DIR="$SCRIPT_DIR/patches"
QLTOGGLE_DIR="$SCRIPT_DIR/QLToggle"
BUILD_DIR="$PM_DIR/build"
INSTALL_DIR="$HOME/Applications"
BUILD_LOG="$SCRIPT_DIR/.last-build.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

echo ""
if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "=== markdown-quicklook build (--check: patch + verify only) ==="
else
    echo "=== markdown-quicklook build ==="
fi
echo ""

# --- Prerequisites ---

command -v git >/dev/null 2>&1 || fail "git not found"
[ -e "$PM_DIR/.git" ] || fail "PreviewMarkdown submodule not found. Run: git submodule update --init"

# --- Reset submodule to pristine (reproducible patch base) ---

git -C "$PM_DIR" reset --hard HEAD >/dev/null
git -C "$PM_DIR" clean -fdx >/dev/null
HEAD_SHA="$(git -C "$PM_DIR" rev-parse HEAD)"
RECORDED_SHA="$(git ls-tree HEAD PreviewMarkdown | awk '{print $3}')"
if [ "$HEAD_SHA" != "$RECORDED_SHA" ]; then
    warn "Building uncommitted submodule revision $HEAD_SHA (recorded: $RECORDED_SHA)."
    warn "If this is an intentional bump, commit the new submodule pointer."
fi
info "Submodule clean at $HEAD_SHA (stubs, assets and build products regenerate below)"

# --- Apply patches ---

info "Applying patches..."

# Stub files
cp "$PATCHES_DIR/REPLACE_WITH_YOUR_FUNCTIONS.swift" "$PM_DIR/"
cp "$PATCHES_DIR/REPLACE_WITH_YOUR_FUNCTIONS.swift" "$PM_DIR/PreviewMarkdown/"
cp "$PATCHES_DIR/REPLACE_WITH_YOUR_CODES.swift" "$PM_DIR/"
cp "$PATCHES_DIR/REPLACE_WITH_YOUR_CODES.swift" "$PM_DIR/PreviewMarkdown/"

# What's New stub
mkdir -p "$PM_DIR/PreviewMarkdown/new"
cat > "$PM_DIR/PreviewMarkdown/new/new.html" <<'HTML'
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>What's New</title></head>
<body><h1>What's New</h1><p>Local build.</p></body></html>
HTML

# Assets.xcassets with color assets for all targets
for TARGET_DIR in "$PM_DIR/PreviewMarkdown" "$PM_DIR/Markdown Previewer" "$PM_DIR/Markdown Thumbnailer"; do
    ASSETS="$TARGET_DIR/Assets.xcassets"
    mkdir -p "$ASSETS/AppIcon.appiconset" "$ASSETS/AccentColor.colorset" \
             "$ASSETS/previewBackground.colorset" "$ASSETS/previewCode.colorset"

    echo '{"info":{"author":"xcode","version":1}}' > "$ASSETS/Contents.json"
    echo '{"colors":[{"idiom":"universal"}],"info":{"author":"xcode","version":1}}' > "$ASSETS/AccentColor.colorset/Contents.json"

    # vC "GitHub Compact": page #FFFFFF / #0D1117, code block #F6F8FA / #151B23
    cat > "$ASSETS/previewBackground.colorset/Contents.json" <<'JSON'
{"colors":[{"color":{"color-space":"srgb","components":{"alpha":"1","blue":"1","green":"1","red":"1"}},"idiom":"universal"},{"appearances":[{"appearance":"luminosity","value":"dark"}],"color":{"color-space":"srgb","components":{"alpha":"1","blue":"0.090","green":"0.067","red":"0.051"}},"idiom":"universal"}],"info":{"author":"xcode","version":1}}
JSON
    cat > "$ASSETS/previewCode.colorset/Contents.json" <<'JSON'
{"colors":[{"color":{"color-space":"srgb","components":{"alpha":"1","blue":"0.980","green":"0.973","red":"0.965"}},"idiom":"universal"},{"appearances":[{"appearance":"luminosity","value":"dark"}],"color":{"color-space":"srgb","components":{"alpha":"1","blue":"0.137","green":"0.106","red":"0.082"}},"idiom":"universal"}],"info":{"author":"xcode","version":1}}
JSON
done

# Generate placeholder icon
python3 -c "
import struct, zlib
w=h=512
raw=b''
for y in range(h):
    raw+=b'\x00'
    for x in range(w):
        raw+=b'\x33\x99\xcc\xff'
sig=b'\x89PNG\r\x1a\n'
def chunk(t,d):
    c=t+d; return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
ihdr=chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))
idat=chunk(b'IDAT',zlib.compress(raw))
iend=chunk(b'IEND',b'')
open('$PM_DIR/PreviewMarkdown/Assets.xcassets/AppIcon.appiconset/icon_512x512.png','wb').write(sig+ihdr+idat+iend)
" || fail "placeholder icon generation failed — is python3 installed?"

cat > "$PM_DIR/PreviewMarkdown/Assets.xcassets/AppIcon.appiconset/Contents.json" <<'JSON'
{"images":[{"filename":"icon_512x512.png","idiom":"mac","scale":"1x","size":"512x512"},{"filename":"icon_512x512.png","idiom":"mac","scale":"2x","size":"256x256"}],"info":{"author":"xcode","version":1}}
JSON

# Patch project.pbxproj
PBXPROJ="$PM_DIR/PreviewMarkdown.xcodeproj/project.pbxproj"

# Fix absolute paths to relative
sed -i '' \
    -e 's|path = "/Users/smitty/Library/Mobile Documents/com~apple~CloudDocs/Documents/Programming/PreviewApps/REPLACE_WITH_YOUR_CODES.swift"; sourceTree = "<absolute>";|path = REPLACE_WITH_YOUR_CODES.swift; sourceTree = "<group>";|g' \
    -e 's|path = "/Users/smitty/Library/Mobile Documents/com~apple~CloudDocs/Documents/Programming/PreviewApps/REPLACE_WITH_YOUR_FUNCTIONS.swift"; sourceTree = "<absolute>";|path = REPLACE_WITH_YOUR_FUNCTIONS.swift; sourceTree = "<group>";|g' \
    -e 's|path = "/Users/smitty/Library/Mobile Documents/com~apple~CloudDocs/Documents/Programming/PreviewMarkdown/Assets.xcassets"; sourceTree = "<absolute>";|path = Assets.xcassets; sourceTree = "<group>";|g' \
    -e 's|path = "/Users/smitty/Library/Mobile Documents/com~apple~CloudDocs/Documents/Programming/PreviewMarkdown/new"; sourceTree = "<absolute>";|path = new; sourceTree = "<group>";|g' \
    -e 's|path = "../../../Library/Mobile Documents/com~apple~CloudDocs/Documents/Programming/PreviewMarkdown/Previewer/Assets.xcassets"; sourceTree = "<group>";|path = Assets.xcassets; sourceTree = "<group>";|g' \
    -e 's|path = "../../Library/Mobile Documents/com~apple~CloudDocs/Documents/Programming/PreviewMarkdown/AppIcon.icon"; sourceTree = SOURCE_ROOT;|path = Assets.xcassets; sourceTree = "<group>";|g' \
    "$PBXPROJ"

# Fix AppIcon.icon type (not iconcomposer — just a folder reference to Assets)
sed -i '' 's|lastKnownFileType = folder.iconcomposer.icon;|lastKnownFileType = folder;|g' "$PBXPROJ"

# Bundle identifiers: com.bps → com.local
sed -i '' 's/com\.bps\.PreviewMarkdown/com.local.PreviewMarkdown/g' "$PBXPROJ"

# Code signing: ad-hoc
sed -i '' \
    -e 's/"DEVELOPMENT_TEAM\[sdk=macosx\*\]" = Y5J3K52DNA;/"DEVELOPMENT_TEAM[sdk=macosx*]" = "";/g' \
    -e 's/CODE_SIGN_IDENTITY = "Apple Development";/CODE_SIGN_IDENTITY = "-";/g' \
    -e 's/"CODE_SIGN_IDENTITY\[sdk=macosx\*\]" = "Apple Development";/"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-";/g' \
    -e 's/"CODE_SIGN_IDENTITY\[sdk=macosx\*\]" = "Developer ID Application";/"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-";/g' \
    -e 's/CODE_SIGN_IDENTITY = "Developer ID Application";/CODE_SIGN_IDENTITY = "-";/g' \
    -e 's/CODE_SIGN_IDENTITY = "3rd Party Mac Developer Application";/CODE_SIGN_IDENTITY = "-";/g' \
    "$PBXPROJ"

# Constants.swift: update bundle ID prefix
sed -i '' 's/com\.bps\.PreviewMarkdown/com.local.PreviewMarkdown/g' "$PM_DIR/PreviewMarkdown/Constants.swift"

# Constants.swift: vC "GitHub Compact" theme defaults
sed -i '' \
    -e 's/"941751FF"/"1F2328FF"/' \
    -e 's/"00FF00FF"/"24292FFF"/' \
    -e 's/"0096FFFF"/"0969DAFF"/' \
    -e 's/"22528EFF"/"59636EFF"/' \
    -e 's/"009193FF"/"0550AEFF"/' \
    -e 's/"AndaleMono"/"Menlo-Regular"/' \
    -E \
    -e 's/(H1[[:space:]]+)=[[:space:]]*2\.6/\1= 1.75/' \
    -e 's/(H2[[:space:]]+)=[[:space:]]*2\.2/\1= 1.4/' \
    -e 's/(H3[[:space:]]+)=[[:space:]]*1\.8/\1= 1.2/' \
    -e 's/(H4[[:space:]]+)=[[:space:]]*1\.4/\1= 1.0/' \
    -e 's/(H5[[:space:]]+)=[[:space:]]*1\.2/\1= 1.0/' \
    -e 's/(H6[[:space:]]+)=[[:space:]]*1\.2/\1= 1.0/' \
    -e 's/(FONT_SIZE[[:space:]]+)=[[:space:]]*16\.0/\1= 14.0/' \
    -e 's/(LINE_SPACING[[:space:]]+)=[[:space:]]*1\.0/\1= 1.45/' \
    -e 's/(PREVIEW_MARGIN_WIDTH[[:space:]]+)=[[:space:]]*16\.0/\1= 28.0/' \
    "$PM_DIR/PreviewMarkdown/Constants.swift"

# PMStyler.swift: vC dark-mode palette + tighter list indent + GitHub highlighter themes.
# The four settings colours are static across modes upstream; light mode keeps
# honouring user settings (displayColours), dark mode uses the shipped vC palette.
sed -i '' \
    -e 's/= NSColor\.hexToColour\(self\.settings!\.displayColours\[BUFFOON_CONSTANTS\.COLOUR_IDS\.HEADS\]!\)/= self.renderLightMode ? NSColor.hexToColour(self.settings!.displayColours[BUFFOON_CONSTANTS.COLOUR_IDS.HEADS]!) : NSColor.hexToColour("E6EDF3FF")/' \
    -e 's/= NSColor\.hexToColour\(self\.settings!\.displayColours\[BUFFOON_CONSTANTS\.COLOUR_IDS\.CODE\]!\)/= self.renderLightMode ? NSColor.hexToColour(self.settings!.displayColours[BUFFOON_CONSTANTS.COLOUR_IDS.CODE]!) : NSColor.hexToColour("E6EDF3FF")/' \
    -e 's/= NSColor\.hexToColour\(self\.settings!\.displayColours\[BUFFOON_CONSTANTS\.COLOUR_IDS\.LINKS\]!\)/= self.renderLightMode ? NSColor.hexToColour(self.settings!.displayColours[BUFFOON_CONSTANTS.COLOUR_IDS.LINKS]!) : NSColor.hexToColour("4493F8FF")/' \
    -e 's/= NSColor\.hexToColour\(self\.settings!\.displayColours\[BUFFOON_CONSTANTS\.COLOUR_IDS\.QUOTES\]!\)/= self.renderLightMode ? NSColor.hexToColour(self.settings!.displayColours[BUFFOON_CONSTANTS.COLOUR_IDS.QUOTES]!) : NSColor.hexToColour("9198A1FF")/' \
    -e 's/\? "atom-one-light" : "atom-one-dark"/? "github" : "github-dark"/' \
    -E \
    -e 's/(firstLineHeadIndent[[:space:]]+)=[[:space:]]*40\.0/\1= 22.0/' \
    "$PM_DIR/Common/PMStyler.swift"

# Entitlements: fix TeamIdentifierPrefix and add sandbox
for ENT in "$PM_DIR/PreviewMarkdown/PreviewMarkdown.entitlements" \
           "$PM_DIR/Markdown Previewer/Previewer.entitlements" \
           "$PM_DIR/Markdown Thumbnailer/Thumbnailer.entitlements" \
           "$PM_DIR/RenderDemo/RenderDemo.entitlements"; do
    if [ -f "$ENT" ]; then
        sed -i '' 's/$(TeamIdentifierPrefix)suite.previewmarkdown/com.local.suite.previewmarkdown/g' "$ENT"
    fi
done

# Extensions MUST be sandboxed — add app-sandbox entitlement
for ENT in "$PM_DIR/Markdown Previewer/Previewer.entitlements" \
           "$PM_DIR/Markdown Thumbnailer/Thumbnailer.entitlements"; do
    if ! grep -q "app-sandbox" "$ENT" 2>/dev/null; then
        sed -i '' 's|<dict>|<dict>\
	<key>com.apple.security.app-sandbox</key>\
	<true/>|' "$ENT"
    fi
done

# Fix tintProminence (requires macOS 26 SDK, not available in Xcode 16)
SETTINGS_FILE="$PM_DIR/PreviewMarkdown/AppDelegateSettings.swift"
if grep -q "self.fontSizeSlider.tintProminence" "$SETTINGS_FILE" 2>/dev/null; then
    sed -i '' '/fontSizeSlider.tintProminence/s/^/\/\/ /' "$SETTINGS_FILE"
fi

info "Patches applied"

# --- Verify patches (outcome assertions — the loud failure mode) ---

verify_patches() {
    local failed=0
    local pbx="$PM_DIR/PreviewMarkdown.xcodeproj/project.pbxproj"
    local constants="$PM_DIR/PreviewMarkdown/Constants.swift"
    local styler="$PM_DIR/Common/PMStyler.swift"

    v_absent()  { if grep -Eq "$3" "$2" 2>/dev/null; then echo "  [✗] $1"; failed=1; else echo "  [✓] $1"; fi; }
    v_present() { if grep -Eq "$3" "$2" 2>/dev/null; then echo "  [✓] $1"; else echo "  [✗] $1"; failed=1; fi; }
    v_min() {
        local n; n=$(grep -Ec "$3" "$2" 2>/dev/null || true)
        if [ "${n:-0}" -ge "$4" ]; then echo "  [✓] $1"; else echo "  [✗] $1 (found ${n:-0}, need ≥ $4)"; failed=1; fi
    }
    v_file()    { if [ -f "$2" ]; then echo "  [✓] $1"; else echo "  [✗] $1"; failed=1; fi; }

    v_absent "pbxproj: no upstream bundle IDs"          "$pbx" 'com\.bps\.PreviewMarkdown'
    v_absent "pbxproj: no absolute home paths"          "$pbx" 'path = "/Users'
    v_absent "pbxproj: no iCloud paths"                 "$pbx" 'Library/Mobile Documents'
    v_absent "pbxproj: no upstream team ID"             "$pbx" 'Y5J3K52DNA'
    v_absent "pbxproj: no iconcomposer file type"       "$pbx" 'folder\.iconcomposer\.icon'
    v_min   "pbxproj: local bundle IDs applied (≥10)"   "$pbx" 'com\.local\.PreviewMarkdown' 10
    v_absent "Constants: no upstream bundle IDs"        "$constants" 'com\.bps\.PreviewMarkdown'
    v_present "Constants: vC heading colour"            "$constants" '1F2328FF'
    v_absent  "Constants: old magenta gone"             "$constants" '941751FF'
    v_absent  "Constants: old pure-green gone"          "$constants" '00FF00FF'
    v_present "Constants: Menlo code font"              "$constants" 'Menlo-Regular'
    v_min    "PMStyler: mode-aware colours (×4)"        "$styler" 'renderLightMode \? NSColor' 4
    v_absent "PMStyler: old highlighter theme gone"     "$styler" 'atom-one'
    v_file "stub present: codes (root)"                 "$PM_DIR/REPLACE_WITH_YOUR_CODES.swift"
    v_file "stub present: codes (target dir)"           "$PM_DIR/PreviewMarkdown/REPLACE_WITH_YOUR_CODES.swift"
    v_file "stub present: functions (root)"             "$PM_DIR/REPLACE_WITH_YOUR_FUNCTIONS.swift"
    v_file "stub present: functions (target dir)"       "$PM_DIR/PreviewMarkdown/REPLACE_WITH_YOUR_FUNCTIONS.swift"

    local ent name
    for ent in "$PM_DIR/PreviewMarkdown/PreviewMarkdown.entitlements" \
               "$PM_DIR/Markdown Previewer/Previewer.entitlements" \
               "$PM_DIR/Markdown Thumbnailer/Thumbnailer.entitlements" \
               "$PM_DIR/RenderDemo/RenderDemo.entitlements"; do
        name="$(basename "$ent")"
        v_present "entitlements rewritten: $name" "$ent" 'com\.local\.suite\.previewmarkdown'
    done
    v_present "Previewer sandboxed"   "$PM_DIR/Markdown Previewer/Previewer.entitlements" 'com\.apple\.security\.app-sandbox'
    v_present "Thumbnailer sandboxed" "$PM_DIR/Markdown Thumbnailer/Thumbnailer.entitlements" 'com\.apple\.security\.app-sandbox'

    if grep 'tintProminence' "$PM_DIR/PreviewMarkdown/AppDelegateSettings.swift" 2>/dev/null | grep -qv '^[[:space:]]*//'; then
        echo "  [✗] tintProminence still uncommented"
        failed=1
    else
        echo "  [✓] tintProminence commented out"
    fi

    return "$failed"
}

echo ""
info "Verifying patches (outcome assertions)..."
VFAIL=0
verify_patches || VFAIL=1

if [ "$CHECK_ONLY" -eq 1 ]; then
    # Always restore the pristine tree in --check mode, pass or fail
    git -C "$PM_DIR" reset --hard HEAD >/dev/null
    git -C "$PM_DIR" clean -fdx >/dev/null
    if [ "$VFAIL" -eq 1 ]; then
        fail "--check: patch verification FAILED (assertions above). Tree restored to pristine; nothing was built or installed."
    fi
    echo ""
    info "--check complete: patches apply cleanly and verify against this submodule revision. Nothing was built or installed."
    exit 0
fi

if [ "$VFAIL" -eq 1 ]; then
    fail "Patch verification FAILED — upstream has drifted from what build.sh expects. See the ✗ assertions above. This build stops here."
fi
info "Patch verification passed"

# --- Build PreviewMarkdown ---

echo ""
info "Building PreviewMarkdown..."

command -v xcodebuild >/dev/null 2>&1 || fail "Xcode command line tools not found. Install with: xcode-select --install"
info "Xcode $(xcodebuild -version 2>&1 | head -1 | awk '{print $2}')"

rm -rf "$BUILD_DIR"
xcodebuild -project "$PM_DIR/PreviewMarkdown.xcodeproj" \
    -scheme PreviewMarkdown \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    DEVELOPMENT_TEAM="" \
    ASSETCATALOG_OTHER_FLAGS="" \
    2>&1 | tee "$BUILD_LOG" | tail -5

PM_APP="$BUILD_DIR/Build/Products/Release/PreviewMarkdown.app"
[ -d "$PM_APP" ] || fail "Build failed — PreviewMarkdown.app not found (full log: $BUILD_LOG)"
info "PreviewMarkdown built"

# Sign
codesign --force --sign - \
    --entitlements "$PM_DIR/Markdown Previewer/Previewer.entitlements" \
    "$PM_APP/Contents/PlugIns/Markdown Previewer.appex" || fail "codesign failed: Markdown Previewer.appex"
codesign --force --sign - \
    --entitlements "$PM_DIR/Markdown Thumbnailer/Thumbnailer.entitlements" \
    "$PM_APP/Contents/PlugIns/Markdown Thumbnailer.appex" || fail "codesign failed: Markdown Thumbnailer.appex"
codesign --force --sign - \
    --entitlements "$PM_DIR/PreviewMarkdown/PreviewMarkdown.entitlements" \
    "$PM_APP" || fail "codesign failed: PreviewMarkdown.app"
info "Signed (ad-hoc)"

# --- Build QLToggle ---

echo ""
info "Building QLToggle..."

QLTOGGLE_BIN="$QLTOGGLE_DIR/QLToggle"
# swiftc doesn't take -arch: compile each slice with its own -target, then lipo
for ARCH in arm64 x86_64; do
    swiftc -o "$QLTOGGLE_BIN.$ARCH" \
        -target "$ARCH-apple-macos13.0" \
        -framework SwiftUI \
        -framework AppKit \
        -framework ServiceManagement \
        -parse-as-library \
        "$QLTOGGLE_DIR/QLToggleApp.swift" 2>&1
done
lipo -create -output "$QLTOGGLE_BIN" "$QLTOGGLE_BIN.arm64" "$QLTOGGLE_BIN.x86_64"
rm -f "$QLTOGGLE_BIN.arm64" "$QLTOGGLE_BIN.x86_64"

QLTOGGLE_APP="$BUILD_DIR/QLToggle.app"
mkdir -p "$QLTOGGLE_APP/Contents/MacOS"
cp "$QLTOGGLE_BIN" "$QLTOGGLE_APP/Contents/MacOS/"
cp "$QLTOGGLE_DIR/Info.plist" "$QLTOGGLE_APP/Contents/"
codesign --force --sign - "$QLTOGGLE_APP" || fail "codesign failed: QLToggle.app"
rm -f "$QLTOGGLE_BIN"
info "QLToggle built"

# --- Install ---

echo ""
mkdir -p "$INSTALL_DIR"

killall PreviewMarkdown 2>/dev/null || true
killall QLToggle 2>/dev/null || true
sleep 1

rm -rf "$INSTALL_DIR/PreviewMarkdown.app"
rm -rf "$INSTALL_DIR/QLToggle.app"
cp -R "$PM_APP" "$INSTALL_DIR/"
cp -R "$QLTOGGLE_APP" "$INSTALL_DIR/"
xattr -dr com.apple.quarantine "$INSTALL_DIR/PreviewMarkdown.app" 2>/dev/null || true
xattr -dr com.apple.quarantine "$INSTALL_DIR/QLToggle.app" 2>/dev/null || true

info "Installed to $INSTALL_DIR"

# --- Register & Launch ---

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$INSTALL_DIR/PreviewMarkdown.app" 2>/dev/null
open "$INSTALL_DIR/PreviewMarkdown.app"
open "$INSTALL_DIR/QLToggle.app"
sleep 3
qlmanage -r >/dev/null 2>&1
qlmanage -r cache >/dev/null 2>&1
info "Extensions registered, Quick Look cache reset"

echo ""
echo -e "${GREEN}Done!${NC} Press Space on any .md file in Finder to preview."
echo "Use the menu bar toggle to switch between rendered/plain text mode."
echo ""
