#!/bin/bash
# One-time preview-settings reset for the vC theme rollout (wrapper v2).
#
# PreviewMarkdown seeds its compiled defaults into the shared suite plist on
# first run and never overwrites existing keys, so machines that ran the old
# magenta/green theme keep those values forever. Run this once after adopting
# the vC theme; the next preview re-seeds with the new defaults.
set -euo pipefail

SUITE="com.local.suite.previewmarkdown"
GROUP_PLIST="$HOME/Library/Group Containers/$SUITE/Library/Preferences/$SUITE.plist"
GLOBAL_PLIST="$HOME/Library/Preferences/$SUITE.plist"

[ -f "$GROUP_PLIST" ] && rm -v "$GROUP_PLIST" || echo "no group-container plist"
[ -f "$GLOBAL_PLIST" ] && rm -v "$GLOBAL_PLIST" || echo "no global plist (research #2's stale copy absent)"

# cfprefsd caches plists; drop the cache so the next read re-seeds from defaults
killall cfprefsd 2>/dev/null || true

echo "Preview settings reset — defaults re-seed on the next preview render."
