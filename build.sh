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
    -e 's/"SFPro-Regular"/"HelveticaNeue"/' \
    -E \
    -e 's/(H1[[:space:]]+)=[[:space:]]*2\.6/\1= 1.75/' \
    -e 's/(H2[[:space:]]+)=[[:space:]]*2\.2/\1= 1.4/' \
    -e 's/(H3[[:space:]]+)=[[:space:]]*1\.8/\1= 1.2/' \
    -e 's/(H4[[:space:]]+)=[[:space:]]*1\.4/\1= 1.0/' \
    -e 's/(H5[[:space:]]+)=[[:space:]]*1\.2/\1= 0.9/' \
    -e 's/(H6[[:space:]]+)=[[:space:]]*1\.2/\1= 0.85/' \
    -e 's/(FONT_SIZE[[:space:]]+)=[[:space:]]*16\.0/\1= 14.0/' \
    -e 's/(LINE_SPACING[[:space:]]+)=[[:space:]]*1\.0/\1= 1.35/' \
    -e 's/(PREVIEW_MARGIN_WIDTH[[:space:]]+)=[[:space:]]*16\.0/\1= 28.0/' \
    -e 's/(BLOCK[[:space:]]+)=[[:space:]]*50\.0/\1= 16.0/' \
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

# --- Measure: cap the prose column at 45em ---
#
# The preview panel is sized as a fraction of the screen (0.75 by default), so
# on any modern display a paragraph runs to ~175 characters per line — roughly
# double the point where the return sweep starts losing the next line. Widen
# the side inset until the column is 45 x the body size (the top of the
# comfortable 45-90 character range) and centre it; the panel keeps its size,
# so code blocks and tables still get the full 45em.
#
# The inset (not the container width) carries the cap on purpose: the container
# keeps tracking the text view, so resizing the panel narrower just narrows the
# column instead of clipping it.
perl -0777 -pi -e 's/                if common\.settings\.previewMarginWidth > 0\.0 \{\n                    self\.renderTextView\.textContainerInset = NSSize\(width: common\.settings\.previewMarginWidth,\n\s+height: common\.settings\.previewMarginWidth\)\n                \}/                let vcMargin: CGFloat = common.settings.previewMarginWidth\n                let vcMeasure: CGFloat = common.settings.fontSize * 45.0\n                let vcInset: CGFloat = max(vcMargin, (self.preferredContentSize.width - vcMeasure) \/ 2.0)\n                self.renderTextView.textContainerInset = NSSize(width: vcInset, height: vcMargin)/' \
    "$PM_DIR/Markdown Previewer/PreviewViewController.swift"
# kbd lozenges are drawn in view coordinates, so they have to be offset by the
# text container inset. Upstream reads `marginDelta`, which assumes the inset is
# square and equal to the margin setting — neither is true once the measure cap
# widens the sides. Read the inset the text view actually has.
perl -0777 -pi -e 's/        lozengeRect\.origin\.x \+= self\.marginDelta\n        lozengeRect\.origin\.y \+= self\.marginDelta/        let lozengeInset: NSSize = self.textContainers.first?.textView?.textContainerInset ?? NSSize(width: self.marginDelta, height: self.marginDelta)\n        lozengeRect.origin.x += lozengeInset.width\n        lozengeRect.origin.y += lozengeInset.height/' \
    "$PM_DIR/Common/PMLayouter.swift"

# vC backgrounds as LITERALS — the Previewer appex ships an empty Assets.car
# (stub colorsets don't compile into that target), so named colors resolve nil
# and nothing paints. Literals are patch-layer-native and catalog-independent.
sed -i '' \
    -e 's/NSColor\.textBackgroundColor$/NSColor(srgbRed: 13 \/ 255.0, green: 17 \/ 255.0, blue: 23 \/ 255.0, alpha: 1)/' \
    "$PM_DIR/Markdown Previewer/PreviewViewController.swift"
# Paragraph gap: upstream hardcodes fontSize * 1.4 (~20pt at 14pt base).
# vC wants 0.75em (10.5pt), which is half a line pitch at the 1.35 leading —
# the point where a paragraph break still reads as a break. Raising the leading
# without raising this makes paragraphs run together.
sed -i '' 's/self\.settings\.fontSize \* 1\.4/self.settings.fontSize * 0.75/' "$PM_DIR/Common/Common.swift"

# The line-spacing popup offers a fixed list of values, and the shipped default
# has to BE one of them: selectItem(at: firstIndex(of: setting) ?? 0) silently
# falls back to the first entry otherwise, so opening Settings and pressing
# Apply would quietly reset the leading to Single. Retitle the 1.15 slot (which
# renders as line-height 1.29 — between the too-tight and the too-airy options,
# and no use to anyone) to the 1.35 the theme now ships.
sed -i '' 's/linespacingValues: \[CGFloat\] = \[1\.0, 1\.15, 1\.5, 2\.0\]/linespacingValues: [CGFloat] = [1.0, 1.35, 1.5, 2.0]/g' \
    "$PM_DIR/PreviewMarkdown/AppDelegateSettings.swift"
sed -i '' 's/title="1\.15"/title="1.35"/g' "$PM_DIR/PreviewMarkdown/Base.lproj/MainMenu.xib"

sed -i '' \
    -e 's/paragraphBlock\.backgroundColor = \.previewCode/paragraphBlock.backgroundColor = self.renderLightMode ? NSColor(srgbRed: 246 \/ 255.0, green: 248 \/ 255.0, blue: 250 \/ 255.0, alpha: 1) : NSColor(srgbRed: 21 \/ 255.0, green: 27 \/ 255.0, blue: 35 \/ 255.0, alpha: 1)/' \
    "$PM_DIR/Common/PMStyler.swift"

# Line-spacing floor: loadSettings' defaults.float(forKey:) returns 0.0 for
# missing keys (fresh install / after reset), and generateStyles turns 0 into
# (0-1)*fontSize = NEGATIVE spacing -> code lines collapse and overlap.
# Floor the guard at 1.0 so anything < 1.0 yields zero extra spacing.
sed -i '' \
    -e 's/self\.settings!\.lineSpacing >= 0\.0 ? self\.settings!\.lineSpacing : 0\.0/self.settings!.lineSpacing >= 1.0 ? self.settings!.lineSpacing : 1.0/' \
    "$PM_DIR/Common/PMStyler.swift"

# Blockquotes: upstream renders bold at 1.6x body size, right-aligned, bare.
# vC: body-size plain text, left-aligned, with GitHub's left rule.
#
# WHERE the rule has to go: styles["blockquote"][.paragraphStyle] is set from
# paragraphs["quote"] at startup, but the renderer REPLACES it with
# makeBlockParagraphStyle(inset) on every content flush inside a quote (see the
# `if isBlockquote` branch), so paragraphs["quote"] never reaches the page.
# Decorating it is dead code — the decoration belongs on the block style.
sed -i '' \
    -e 's/makeFont("strong", self\.settings!\.fontSize \* BUFFOON_CONSTANTS\.MULTIPLIER\.BLOCK)/makeFont("plain", self.settings!.fontSize)/' \
    "$PM_DIR/Common/PMStyler.swift"
perl -pi -e 's/^\s*self\.paragraphs\["quote"\]\s*=\s*quoteParaStyle$/        quoteParaStyle.alignment = .left\n        self.paragraphs["quote"] = quoteParaStyle/' \
    "$PM_DIR/Common/PMStyler.swift"
# The rule itself: a 4pt .minX border on the block cell the renderer actually
# uses, plus padding so the quote sits inside its own column. Per-edge border
# colours DO render — the previewer draws through NSTextView/NSLayoutManager,
# which honours them. (They are invisible under NSAttributedString.draw(in:),
# a different engine that drops most NSTextBlock decoration; measuring there
# is what previously "proved" borders impossible.)
perl -pi -e 's/^(\s*)newParaStyle\.firstLineHeadIndent = newParaStyle\.headIndent$/$1newParaStyle.firstLineHeadIndent = newParaStyle.headIndent\n$1let quoteTable: NSTextTable = NSTextTable()\n$1quoteTable.numberOfColumns = 1\n$1quoteTable.collapsesBorders = true\n$1let quoteCell: NSTextTableBlock = NSTextTableBlock(table: quoteTable, startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)\n$1quoteCell.setWidth(4.0, type: .absoluteValueType, for: .border, edge: .minX)\n$1quoteCell.setBorderColor(self.renderLightMode ? NSColor(srgbRed: 208 \/ 255.0, green: 215 \/ 255.0, blue: 222 \/ 255.0, alpha: 1) : NSColor(srgbRed: 61 \/ 255.0, green: 68 \/ 255.0, blue: 77 \/ 255.0, alpha: 1), for: .minX)\n$1quoteCell.setWidth(24.0, type: .absoluteValueType, for: .padding, edge: .minX)\n$1quoteCell.setWidth(2.0, type: .absoluteValueType, for: .padding, edge: .minY)\n$1quoteCell.setWidth(2.0, type: .absoluteValueType, for: .padding, edge: .maxY)\n$1newParaStyle.textBlocks = [quoteCell]/' \
    "$PM_DIR/Common/PMStyler.swift"

# --- Typography: one readable ladder instead of many near-identical styles ---
#
# Upstream's ladder collapses at the bottom (H4/H5/H6 all body-size, and H6 not
# even bold) so three heading levels render identically, while inline CODE and
# CODE inside a blockquote render LARGER than the prose around them. The result
# is a page full of apparent "styles" that carry no information. vC:
#
#   H1 1.75  H2 1.4  H3 1.2  H4 1.0  H5 0.9  H6 0.85 bold + muted grey
#   inline code 0.9x — Menlo runs optically large, so 0.9 matches the body's
#                      apparent size instead of shouting over it
#   block code  1.0x — stands alone in its own panel, untouched (renderCode
#                      never consults styles["code"], so this falls out free)
#
# H5/H6 sizes are floored so the 10pt font setting can't shrink them below
# legibility, and H1/H2/H3 get extra space ABOVE them so hierarchy is carried
# by air as much as by point size.
sed -i '' -E \
    -e 's/self\.colours\.body  = self\.renderLightMode \? \.black : \.white/self.colours.body  = self.renderLightMode ? NSColor.hexToColour("1F2328FF") : NSColor.hexToColour("E6EDF3FF")/' \
    -e 's/makeFont\("strong", self\.settings!\.fontSize \* BUFFOON_CONSTANTS\.MULTIPLIER\.H5\)/makeFont("strong", max(self.settings!.fontSize * BUFFOON_CONSTANTS.MULTIPLIER.H5, 11.0))/' \
    -e 's/makeFont\("code", setFontSize\(parentStyle\.name\)\)/makeFont("code", max(setFontSize(parentStyle.name) * 0.9, 11.0))/' \
    -e 's/cellFont = self\.makeFont\("code", self\.settings!\.fontSize\)/cellFont = self.makeFont("code", max(self.settings!.fontSize * 0.9, 11.0))/' \
    -e 's/border:0\.5px solid #444444;/border:0.5px solid #\\(self.renderLightMode ? "D0D7DE" : "30363D");/' \
    "$PM_DIR/Common/PMStyler.swift"

# H6: upstream is the ONLY heading rendered at "plain" weight, which — at
# body size — makes it indistinguishable from a paragraph. Bold it, floor it,
# and mute the colour so it reads as the quietest step, not a broken one.
perl -0777 -pi -e 's/self\.styles\["h6"\](\s+)= \[\.foregroundColor: self\.colours\.head,\n(\s+)\.font: makeFont\("plain", self\.settings!\.fontSize \*\s+BUFFOON_CONSTANTS\.MULTIPLIER\.H6\),/self.styles["h6"]$1= [.foregroundColor: self.renderLightMode ? NSColor.hexToColour("6E7781FF") : NSColor.hexToColour("7D8590FF"),\n$2.font: makeFont("strong", max(self.settings!.fontSize * BUFFOON_CONSTANTS.MULTIPLIER.H6, 10.5)),/' \
    "$PM_DIR/Common/PMStyler.swift"

# Inline code: 0.9x body size on the same tint as the code-block panel.
perl -0777 -pi -e 's/self\.styles\["code"\](\s+)= \[\.foregroundColor: self\.colours\.code,\n(\s+)\.font: makeFont\("code", self\.settings!\.fontSize\)\]/self.styles["code"]$1= [.foregroundColor: self.colours.code,\n$2.backgroundColor: self.renderLightMode ? NSColor(srgbRed: 246 \/ 255.0, green: 248 \/ 255.0, blue: 250 \/ 255.0, alpha: 1) : NSColor(srgbRed: 21 \/ 255.0, green: 27 \/ 255.0, blue: 35 \/ 255.0, alpha: 1),\n$2.font: makeFont("code", max(self.settings!.fontSize * 0.9, 11.0))]/' \
    "$PM_DIR/Common/PMStyler.swift"

# setFontSize BUG: "h4" falls through to "blockquote" and both return 1.6x, so
# inline code inside an H4 or a blockquote renders at 22pt against 14pt prose.
# H4 gets its own multiplier; a blockquote is body-size by definition.
perl -0777 -pi -e 's/case "h4":\n(\s+)fallthrough\n(\s+)case "blockquote":\n(\s+)return self\.settings!\.fontSize \* BUFFOON_CONSTANTS\.MULTIPLIER\.BLOCK\n/case "h4":\n$3return self.settings!.fontSize * BUFFOON_CONSTANTS.MULTIPLIER.H4\n$2case "blockquote":\n$3return self.settings!.fontSize\n/' \
    "$PM_DIR/Common/PMStyler.swift"

# Space above headings: every block shares paragraphs["tabbed"], so a heading
# gets exactly as much air as the paragraph before it. Give h1/h2/h3 their own
# copies with paragraphSpacingBefore scaled to their weight in the outline.
perl -0777 -pi -e 's/^(\s*)self\.paragraphs\["tabbed"\](\s+)= tabbedParaStyle$/$1self.paragraphs["tabbed"]$2= tabbedParaStyle\n\n$1for (headTag, headSpacing) in [("h1", 2.0), ("h2", 1.5), ("h3", 1.1)] as [(String, CGFloat)] {\n$1    let headParaStyle: NSMutableParagraphStyle = tabbedParaStyle.mutableCopy() as! NSMutableParagraphStyle\n$1    headParaStyle.paragraphSpacingBefore = self.paraSpacing * headSpacing\n$1    self.paragraphs[headTag] = headParaStyle\n$1}/m' \
    "$PM_DIR/Common/PMStyler.swift"
perl -0777 -pi -e 'for my $h (qw(h1 h2 h3)) { s/(self\.styles\["$h"\]\s+= \[.*?\.paragraphStyle: self\.paragraphs\[")tabbed("\]!\])/$1$h$2/s }' \
    "$PM_DIR/Common/PMStyler.swift"

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
    v_present "Constants: HelveticaNeue body font"     "$constants" 'HelveticaNeue'
    v_absent  "Constants: unresolvable SFPro-Regular"    "$constants" 'SFPro-Regular'
    v_absent  "Constants: non-enumerable system font"    "$constants" 'AppleSystemUIFont'
    v_present "Constants: H1 ladder step 1.75"          "$constants" 'H1[[:space:]]+= 1\.75$'
    v_present "Constants: H2 ladder step 1.4"           "$constants" 'H2[[:space:]]+= 1\.4$'
    v_present "Constants: H3 ladder step 1.2"           "$constants" 'H3[[:space:]]+= 1\.2$'
    v_present "Constants: H4 ladder step 1.0"           "$constants" 'H4[[:space:]]+= 1\.0$'
    v_present "Constants: H5 ladder step 0.9"           "$constants" 'H5[[:space:]]+= 0\.9$'
    v_present "Constants: H6 ladder step 0.85"          "$constants" 'H6[[:space:]]+= 0\.85$'
    v_absent  "Constants: upstream 2.6x H1 gone"        "$constants" 'H1[[:space:]]+= 2\.6'
    v_min    "PMStyler: mode-aware colours (×4)"        "$styler" 'renderLightMode \? NSColor' 4
    v_present "PMStyler: literal code-block background" "$styler" 'srgbRed: 21'
    v_present "PMStyler: line-spacing floor"           "$styler" 'lineSpacing >= 1.0'
    v_present "Constants: 1.35 leading (line-height 1.49)" "$constants" 'LINE_SPACING[[:space:]]+= 1\.35'
    v_present "Common: paragraph gap 0.75em"           "$PM_DIR/Common/Common.swift" 'fontSize \* 0\.75'
    v_present "Settings: popup offers the shipped 1.35" "$PM_DIR/PreviewMarkdown/AppDelegateSettings.swift" 'linespacingValues: \[CGFloat\] = \[1\.0, 1\.35, 1\.5, 2\.0\]'
    v_absent  "Settings: unreachable 1.15 slot gone"   "$PM_DIR/PreviewMarkdown/AppDelegateSettings.swift" '1\.0, 1\.15,'
    v_present "XIB: popup item matches the default"    "$PM_DIR/PreviewMarkdown/Base.lproj/MainMenu.xib" 'title="1\.35"'
    v_absent  "XIB: stale 1.15 item gone"              "$PM_DIR/PreviewMarkdown/Base.lproj/MainMenu.xib" 'title="1\.15"'
    v_present "Constants: blockquote inset 16"          "$constants" 'BLOCK[[:space:]]+= 16\.0'
    v_present "PMStyler: blockquote left-aligned"      "$styler" 'quoteParaStyle\.alignment = \.left'
    v_present "PMStyler: blockquote rule colour"       "$styler" 'quoteCell\.setBorderColor\('
    v_present "PMStyler: rule on the style that ships" "$styler" 'newParaStyle\.textBlocks = \[quoteCell\]'
    v_absent  "PMStyler: no 1.6x block multiplier left" "$styler" 'MULTIPLIER\.BLOCK'
    v_present "PMStyler: h4 sized by its own step"     "$styler" 'return self\.settings!\.fontSize \* BUFFOON_CONSTANTS\.MULTIPLIER\.H4'
    v_present "PMStyler: vC body ink, not pure b/w"    "$styler" 'colours\.body  = self\.renderLightMode \? NSColor\.hexToColour\("1F2328FF"\)'
    v_absent  "PMStyler: .black/.white body gone"      "$styler" 'colours\.body  = self\.renderLightMode \? \.black'
    v_present "PMStyler: H5 legibility floor"          "$styler" 'makeFont\("strong", max\(self\.settings!\.fontSize \* BUFFOON_CONSTANTS\.MULTIPLIER\.H5, 11\.0\)\)'
    v_present "PMStyler: H6 bold + floor"              "$styler" 'makeFont\("strong", max\(self\.settings!\.fontSize \* BUFFOON_CONSTANTS\.MULTIPLIER\.H6, 10\.5\)\)'
    v_present "PMStyler: H6 muted grey"                "$styler" 'NSColor\.hexToColour\("7D8590FF"\)'
    v_absent  "PMStyler: plain-weight H6 gone"         "$styler" 'makeFont\("plain", self\.settings!\.fontSize \*[[:space:]]+BUFFOON_CONSTANTS\.MULTIPLIER\.H6'
    v_present "PMStyler: inline code 0.9x"             "$styler" 'makeFont\("code", max\(self\.settings!\.fontSize \* 0\.9, 11\.0\)\)'
    v_present "PMStyler: inline code tint"             "$styler" 'backgroundColor: self\.renderLightMode \? NSColor\(srgbRed: 246'
    v_present "PMStyler: code-in-heading scaled too"   "$styler" 'makeFont\("code", max\(setFontSize\(parentStyle\.name\) \* 0\.9, 11\.0\)\)'
    v_present "PMStyler: table inline code 0.9x"       "$styler" 'cellFont = self\.makeFont\("code", max\('
    v_present "PMStyler: heading spacing styles built" "$styler" 'self\.paragraphs\[headTag\] = headParaStyle'
    v_min    "PMStyler: h1/h2/h3 own para styles (×3)" "$styler" 'paragraphStyle: self\.paragraphs\["h[123]"\]!\]' 3
    v_present "PMStyler: mode-aware table borders"     "$styler" 'renderLightMode \? "D0D7DE" : "30363D"'
    v_absent  "PMStyler: washed-out table borders gone" "$styler" 'solid #444444'
    v_present "Previewer: literal page background"      "$PM_DIR/Markdown Previewer/PreviewViewController.swift" 'srgbRed: 13'
    v_present "Previewer: 45em measure cap"             "$PM_DIR/Markdown Previewer/PreviewViewController.swift" 'vcMeasure: CGFloat = common\.settings\.fontSize \* 45\.0'
    v_present "Previewer: measure cap centres column"   "$PM_DIR/Markdown Previewer/PreviewViewController.swift" 'max\(vcMargin, \(self\.preferredContentSize\.width - vcMeasure\) / 2\.0\)'
    v_absent  "Previewer: square margin inset gone"     "$PM_DIR/Markdown Previewer/PreviewViewController.swift" 'NSSize\(width: common\.settings\.previewMarginWidth,'
    v_present "PMLayouter: lozenge uses real inset"     "$PM_DIR/Common/PMLayouter.swift" 'lozengeRect\.origin\.x \+= lozengeInset\.width'
    v_absent  "PMLayouter: square marginDelta gone"     "$PM_DIR/Common/PMLayouter.swift" 'origin\.y \+= self\.marginDelta'
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