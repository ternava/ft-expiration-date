#!/usr/bin/env bash
set -uo pipefail

# Extracts feature flags from Vespa's Flags.java and PermanentFlags.java.
#
# Usage: 
#       ./01-extract-feature-flags-vespa.sh [VESPA_DIR] [OUTPUT_CSV]
#
# Flags.java: Regular flags with real expiration dates
# PermanentFlags.java: Permanent flags (expire 2100-01-01, no owners)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VESPA_DIR="${1:-$SCRIPT_DIR/../../codebases/vespa}"
OUTPUT_FILE="${2:-$SCRIPT_DIR/../data/01-vespa-feature-flags.csv}"
FLAGS_DIR="$VESPA_DIR/flags/src/main/java/com/yahoo/vespa/flags"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Write CSV header
echo "flag_name,flag_type,default_value,owners,created_at,expires_at,description,modification_effect,dimensions,is_permanent" > "$OUTPUT_FILE"

# Function to extract flags from a file
extract_flags() {
    local file="$1"
    local is_permanent="$2"
    
    awk '
    /= define.*Flag\(/ { collecting = 1; line = $0; next }
    collecting {
        line = line " " $0
        if (/\);/) {
            gsub(/[[:space:]]+/, " ", line)
            gsub(/" \+ "/, "", line)
            print line
            collecting = 0
        }
    }
    ' "$file" | while read -r line; do
        
        # Determine flag type
        case "$line" in
            *defineFeatureFlag*) type="boolean" ;;
            *defineStringFlag*)  type="string" ;;
            *defineIntFlag*)     type="int" ;;
            *defineLongFlag*)    type="long" ;;
            *defineDoubleFlag*)  type="double" ;;
            *defineJacksonFlag*) type="jackson" ;;
            *defineListFlag*)    type="list" ;;
            *) continue ;;
        esac
        
        # Extract flag name (first quoted string)
        name=$(echo "$line" | grep -oP '"\K[^"]+' | head -1)
        
        if [[ "$is_permanent" == "true" ]]; then
            # Permanent flags: no dates in the definition, use hardcoded values
            created="1970-01-01"
            expires="2100-01-01"
            owners=""
            
            # For permanent flags: defineXxxFlag("name", default, "desc", "effect", DIMS)
            # Description and effect are the last two quoted strings before dimensions
            all_strings=$(echo "$line" | grep -oP '"[^"]+"' | tr -d '"')
            desc=$(echo "$all_strings" | tail -2 | head -1 || true)
            effect=$(echo "$all_strings" | tail -1 || true)
        else
            # Regular flags: extract dates and owners
            created=$(echo "$line" | grep -oP '\d{4}-\d{2}-\d{2}' | head -1)
            expires=$(echo "$line" | grep -oP '\d{4}-\d{2}-\d{2}' | tail -1)
            
            # Extract owners from List.of("owner1", "owner2")
            if [[ "$type" == "list" ]]; then
                owners=$(echo "$line" | sed 's/.*\.class[[:space:]]*,//' | grep -oP 'List\.of\("[^)]+\)' | head -1 | grep -oP '"[^"]+"' | tr -d '"' | tr '\n' ';' | sed 's/;$//' || true)
            else
                owners=$(echo "$line" | grep -oP 'List\.of\("[^)]+\)' | head -1 | grep -oP '"[^"]+"' | tr -d '"' | tr '\n' ';' | sed 's/;$//' || true)
            fi
            
            # Description and effect: strings after the expires date
            rest=$(echo "$line" | sed "s/.*$expires\",//")
            desc=$(echo "$rest" | grep -oP '"\K[^"]+' | head -1 || true)
            effect=$(echo "$rest" | grep -oP '"\K[^"]+' | head -2 | tail -1 || true)
        fi
        
        # Extract default value based on type
        case "$type" in
            boolean) default=$(echo "$line" | grep -oP 'Flag\(\s*"[^"]+"\s*,\s*\K(true|false)' || true) ;;
            string)  default=$(echo "$line" | grep -oP 'Flag\(\s*"[^"]+"\s*,\s*"\K[^"]*' || true) ;;
            int|long) default=$(echo "$line" | grep -oP 'Flag\(\s*"[^"]+"\s*,\s*\K-?[0-9]+' || true) ;;
            double)  default=$(echo "$line" | grep -oP 'Flag\(\s*"[^"]+"\s*,\s*\K-?[0-9.]+' || true) ;;
            list)    default="List.of()" ;;
            jackson) default=$(echo "$line" | grep -oP 'Flag\(\s*"[^"]+"\s*,\s*\K[^,]+' | tr -d ' ' || true) ;;
        esac
        
        # Replace commas with semicolons
        desc="${desc//,/;}"
        effect="${effect//,/;}"
        
        # Extract dimensions (uppercase identifiers at the end)
        dims=$(echo "$line" | grep -oP '[A-Z_]+(?=\s*[,)])' | grep -vE '^(List|Flag)$' | tr '\n' ',' | sed 's/,$//' || true)
        
        # Output CSV row
        [[ -n "$name" ]] && \
            echo "\"$name\",\"$type\",\"$default\",\"$owners\",\"$created\",\"$expires\",\"$desc\",\"$effect\",\"$dims\",\"$is_permanent\""
    done
}

# Extract from both files
extract_flags "$FLAGS_DIR/Flags.java" "false" >> "$OUTPUT_FILE"
extract_flags "$FLAGS_DIR/PermanentFlags.java" "true" >> "$OUTPUT_FILE"

# Summary
total=$(tail -n +2 "$OUTPUT_FILE" | wc -l)
regular=$(grep -c '"false"$' "$OUTPUT_FILE" || true)
permanent=$(grep -c '"true"$' "$OUTPUT_FILE" || true)
echo "Total: $total flags ($regular regular + $permanent permanent) | Output: $OUTPUT_FILE"
