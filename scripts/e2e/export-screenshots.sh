#!/usr/bin/env bash
# Saves the screenshots ScreenshotTests kept in a test result bundle as docs/screenshots/<screen>-<appearance>.png.
# Usage: export-screenshots.sh build/UITests.xcresult [docs/screenshots]
set -euo pipefail

RESULT="${1:?usage: $0 RESULT.xcresult [OUTPUT_DIR]}"
OUTPUT="${2:-docs/screenshots}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun xcresulttool export attachments --path "$RESULT" --output-path "$WORK"
mkdir -p "$OUTPUT"
# manifest.json lists each test's attachments with the file it was exported to and the name the test gave it.
jq -r '.[].attachments[] | [.exportedFileName, .suggestedHumanReadableName] | @tsv' "$WORK/manifest.json" |
    while IFS=$'\t' read -r file name; do
        # Names come back as "<name>_<index>_<uuid>.png"; keep just the test's name.
        screen="${name%%_*}"
        case "$screen" in
            *-light | *-dark) cp "$WORK/$file" "$OUTPUT/$screen.png" && echo "$OUTPUT/$screen.png" ;;
        esac
    done
