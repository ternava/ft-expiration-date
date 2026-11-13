#!/usr/bin/env bash
set -euo pipefail

# Extracts all feature gates from Kubernetes with lifecycle and expiration metadata.
#
# Usage: ./02-extract-feature-gates-kubernetes.sh [K8S_DIR] [OUTPUT_CSV]
#   K8S_DIR    - Path to Kubernetes source (default: ../../codebases/kubernetes)
#   OUTPUT_CSV - Output file path (default: ../data/02-kubernetes-feature-gates.csv)
#
# Parses all kube_features.go files and extracts VersionedSpecs maps containing:
#   - Feature gate name and current lifecycle stage (Alpha/Beta/GA/Deprecated)
#   - Default value and LockToDefault status
#   - Version when added and deprecated
#   - Removal version from inline comments (e.g., "// remove in 1.38")
#
# Output: CSV with has_expiration=true for deprecated gates or those with removal info.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${1:-$SCRIPT_DIR/../../codebases/kubernetes}"
OUT_CSV="${2:-$SCRIPT_DIR/../data/01-kubernetes-feature-gates.csv}"

mkdir -p "$(dirname "$OUT_CSV")"
echo "gate_name,stage,default_value,lock_to_default,version_added,version_deprecated,removal_version,expiration_comment,has_expiration,source_file" > "$OUT_CSV"

# Find and process all kube_features.go files
for FEATURES_FILE in $(find "$K8S_DIR" -name "kube_features.go" -type f 2>/dev/null); do
    REL_PATH="${FEATURES_FILE#$K8S_DIR/}"
    
    # Find all VersionedSpecs maps
    for map_start in $(grep -n "map\[featuregate.Feature\]featuregate.VersionedSpecs{" "$FEATURES_FILE" 2>/dev/null | cut -d: -f1); do
        map_end=$(awk "NR > $map_start && /^}$/ {print NR; exit}" "$FEATURES_FILE")
        [[ -z "$map_end" ]] && continue
        
        sed -n "${map_start},${map_end}p" "$FEATURES_FILE" | awk -v rel_path="$REL_PATH" '
/^[[:space:]]*[a-zA-Z][a-zA-Z0-9_.]*:[[:space:]]*{[[:space:]]*$/ {
    match($0, /^[[:space:]]*([a-zA-Z][a-zA-Z0-9_.]*):/, arr)
    current_gate = arr[1]; in_specs = 1; spec_count = 0
    version_added = ""; version_deprecated = ""; removal_version = ""; expiration_comment = ""
    current_stage = ""; current_default = ""; current_lock = "false"
    next
}

in_specs && /^[[:space:]]*},[[:space:]]*$/ {
    in_specs = 0
    if (spec_count > 0 && current_gate != "") {
        has_exp = (current_stage == "Deprecated" || version_deprecated != "" || removal_version != "" || expiration_comment != "") ? "true" : "false"
        gsub(/[[:space:]]/, "", current_default)
        # Escape quotes in comment for CSV (quotes already wrapped)
        gsub(/"/, "\"\"", expiration_comment)
        # Replace commas with semicolons in comment to avoid CSV parsing issues
        gsub(/,/, ";", expiration_comment)
        print current_gate "," current_stage "," current_default "," current_lock "," version_added "," version_deprecated "," removal_version ",\"" expiration_comment "\"," has_exp "," rel_path
    }
    next
}

in_specs && /\{Version:[[:space:]]*version\.MustParse\(/ {
    spec_count++
    # Capture removal/expiration comment from inline comment
    if ($0 ~ /\/\//) {
        match($0, /\/\/[[:space:]]*(.*)$/, arr)
        comment = arr[1]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", comment)
        if (comment ~ /[Rr]emove|[Dd]eprecate|GA/) {
            expiration_comment = comment
            # removal version = version after "remove" (not the first version, e.g. "GA in 1.30; remove in 1.32")
            if (match(comment, /[Rr]emove[^0-9]*v?([0-9]+\.[0-9]+)/, ver)) {
                removal_version = ver[1]
            }
        }
    }
    match($0, /Version:[[:space:]]*version\.MustParse\("([^"]+)"/, arr); version = arr[1]
    match($0, /Default:[[:space:]]*([a-z]+)/, arr); current_default = arr[1]
    match($0, /PreRelease:[[:space:]]*featuregate\.([A-Za-z]+)/, arr); current_stage = arr[1]
    if ($0 ~ /LockToDefault:[[:space:]]*true/) current_lock = "true"
    if (current_stage == "Deprecated" && version_deprecated == "") version_deprecated = version
    if (version_added == "") version_added = version
}

# Capture standalone comment lines (e.g., TODO comments) with removal/expiration info
in_specs && /^[[:space:]]*\/\// && !/\{Version:/ {
    match($0, /\/\/[[:space:]]*(.*)$/, arr)
    comment = arr[1]
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", comment)
    if (comment ~ /[Rr]emove|[Dd]eprecate/) {
        if (expiration_comment == "") {
            expiration_comment = comment
        }
        # Extract version number if present
        if (removal_version == "" && match(comment, /[Rr]emove[^0-9]*v?([0-9]+\.[0-9]+)/, ver)) {
            removal_version = ver[1]
        }
    }
}
'
    done
done >> "$OUT_CSV"

# Deduplicate: prefer staging files over main file references
tmp_file=$(mktemp)
head -1 "$OUT_CSV" > "$tmp_file"
tail -n +2 "$OUT_CSV" | awk -F',' '{
    base = $1; gsub(/.*\./, "", base)
    if (!(base in seen) || ($10 ~ /staging/ && seen[base] !~ /staging/)) seen[base] = $0
} END { for (n in seen) print seen[n] }' | sort -t',' -k1,1 >> "$tmp_file"
mv "$tmp_file" "$OUT_CSV"

# Summary
total=$(tail -n +2 "$OUT_CSV" | wc -l)
with_exp=$(tail -n +2 "$OUT_CSV" | awk -F',' '$9=="true"' | wc -l)
echo "Total: $total | With expiration: $with_exp ($(awk "BEGIN {printf \"%.1f\", $with_exp * 100 / $total}")%)"
echo "Output: $OUT_CSV"