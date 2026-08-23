#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PM_DIR="$SCRIPT_DIR/PreviewMarkdown"
PATCHES_DIR="$SCRIPT_DIR/patches"
QLTOGGLE_DIR="$SCRIPT_DIR/QLToggle"
BUILD_DIR="$PM_DIR/build"
INSTALL_DIR="$HOME/Applications"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# --- Prerequisites ---

echo ""
echo "=== markdown-quicklook build ==="
echo ""

command -v xcodebuild >/dev/null 2>&1 || fail "Xcode command line tools not found. Install with: xcode-select --install"
info "Xcode $(xcodebuild -version 2>&1 | head -1 | awk '{print $2}')"

[ -e "$PM_DIR/.git" ] || fail "PreviewMarkdown submodule not found. Run: git submodule update --init"
info "PreviewMarkdown submodule OK"

# --- Apply patches ---

echo ""
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
sig=b'\x89PNG\r\n\x1a\n'
def chunk(t,d):
    c=t+d; return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
ihdr=chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))
idat=chunk(b'IDAT',zlib.compress(raw))
iend=chunk(b'IEND',b'')
open('$PM_DIR/PreviewMarkdown/Assets.xcassets/AppIcon.appiconset/icon_512x512.png','wb').write(sig+ihdr+idat+iend)
" 2>/dev/null

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

# --- Build PreviewMarkdown ---

echo ""
info "Building PreviewMarkdown..."

rm -rf "$BUILD_DIR"
xcodebuild -project "$PM_DIR/PreviewMarkdown.xcodeproj" \
    -scheme PreviewMarkdown \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    DEVELOPMENT_TEAM="" \
    ASSETCATALOG_OTHER_FLAGS="" \
    2>&1 | tail -5

PM_APP="$BUILD_DIR/Build/Products/Release/PreviewMarkdown.app"
[ -d "$PM_APP" ] || fail "Build failed — PreviewMarkdown.app not found"
info "PreviewMarkdown built"

# Sign
codesign --force --sign - \
    --entitlements "$PM_DIR/Markdown Previewer/Previewer.entitlements" \
    "$PM_APP/Contents/PlugIns/Markdown Previewer.appex" 2>/dev/null
codesign --force --sign - \
    --entitlements "$PM_DIR/Markdown Thumbnailer/Thumbnailer.entitlements" \
    "$PM_APP/Contents/PlugIns/Markdown Thumbnailer.appex" 2>/dev/null
codesign --force --sign - \
    --entitlements "$PM_DIR/PreviewMarkdown/PreviewMarkdown.entitlements" \
    "$PM_APP" 2>/dev/null
info "Signed (ad-hoc)"

# --- Build QLToggle ---

echo ""
info "Building QLToggle..."

QLTOGGLE_BIN="$QLTOGGLE_DIR/QLToggle"
swiftc -o "$QLTOGGLE_BIN" \
    -target arm64-apple-macos13.0 \
    -framework SwiftUI \
    -framework AppKit \
    -parse-as-library \
    "$QLTOGGLE_DIR/QLToggleApp.swift" 2>&1

QLTOGGLE_APP="$BUILD_DIR/QLToggle.app"
mkdir -p "$QLTOGGLE_APP/Contents/MacOS"
cp "$QLTOGGLE_BIN" "$QLTOGGLE_APP/Contents/MacOS/"
cp "$QLTOGGLE_DIR/Info.plist" "$QLTOGGLE_APP/Contents/"
codesign --force --sign - "$QLTOGGLE_APP" 2>/dev/null
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
