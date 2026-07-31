#!/usr/bin/env bash
set -euo pipefail

# Extract Chromium feature flags with expiration metadata
# Usage: ./scripts/01-extract-feature-flags-chromium.sh [<chromium-codebase-path>] [<output-csv-path>]
# Requires: jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROMIUM_DIR="${1:-$SCRIPT_DIR/../../codebases/chromium}"
OUT_CSV="${2:-$SCRIPT_DIR/../data/01-chromium-feature-flags.csv}"

FLAG_METADATA="$CHROMIUM_DIR/chrome/browser/flag-metadata.json"

mkdir -p "$(dirname "$OUT_CSV")"

# This will remove // comments from JSON (only at start of line, not inside strings)
remove_comments() {
    sed 's/^[[:space:]]*\/\/.*$//' | sed 's/,\([[:space:]]*[]}]\)/\1/g'
}

# Write CSV header
echo "flag_name,has_expiration,expiry_milestone,is_never_expire,expiration_status,owners,owner_count" > "$OUT_CSV"

# How we define expiration_status below:
# Condition	| has_expiration | is_never_expire	| expiration_status
# expiry_milestone is a positive number	| True	| False	| "Has Expiration"
# expiry_milestone is -1	| False	| True	| "Never Expires"
# expiry_milestone is missing/null	| False	| False	| "No Expiration Set"

remove_comments < "$FLAG_METADATA" | jq -r '.[] | [
    .name,
    (if .expiry_milestone != null and .expiry_milestone != -1 then "True" else "False" end),
    (.expiry_milestone // ""),
    (if .expiry_milestone == -1 then "True" else "False" end),
    (if .expiry_milestone == -1 then "Never Expires"
     elif .expiry_milestone == null then "No Expiration Set"
     else "Has Expiration" end),
    ((.owners // []) | join(";")),
    ((.owners // []) | length)
] | @csv' >> "$OUT_CSV"

echo "Extracted $(tail -n +2 "$OUT_CSV" | wc -l) flags to $OUT_CSV"
