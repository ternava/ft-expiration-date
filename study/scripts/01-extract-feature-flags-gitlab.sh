#!/usr/bin/env bash
set -euo pipefail

# 01-extract-feature-flags-gitlab.sh
# Extracts all feature flags from GitLab codebase, milestone/rollout_issue_url may be blank.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITLAB_DIR="${1:-$SCRIPT_DIR/../../codebases/gitlab}"
OUT_CSV="${2:-$SCRIPT_DIR/../data/01-gitlab-feature-flags.csv}"

# Create the output file if it doesn't exist
mkdir -p "$(dirname "$OUT_CSV")"

# Write CSV header
echo "flag_name,milestone,rollout_issue_url,definition_file" > "$OUT_CSV"

# Feature flags are defined in YAML files under config/feature_flags
# Find all feature flag YAML definition files
find "$GITLAB_DIR/config/feature_flags" -type f -name "*.yml" | while read -r file
do
  flag_name=$(basename "$file" .yml)
  # Default to empty if not found
  milestone=""
  rollout_issue_url=""
  if grep -qE '^milestone:' "$file"
  then
    milestone=$(grep -E '^milestone:' "$file" | head -1 | sed "s/milestone:[ ]*//;s/\"//g;s/'//g")
  fi
  if grep -qE '^rollout_issue_url:' "$file"
  then
    rollout_issue_url=$(grep -E '^rollout_issue_url:' "$file" | head -1 | sed "s/rollout_issue_url:[ ]*//;s/\"//g;s/'//g")
  fi
  printf '%s,%s,%s,%s\n' "$flag_name" "$milestone" "$rollout_issue_url" "$file" >> "$OUT_CSV"
done

echo "Extraction complete. Results saved to $OUT_CSV"
