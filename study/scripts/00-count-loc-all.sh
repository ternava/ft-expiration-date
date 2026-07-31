#!/usr/bin/env bash
set -euo pipefail

# Simple LOC counting script using cloc
# For each project, run: cloc --timeout 0 --csv codebases/<project>/
# Aggregate SUM rows into a single CSV: ./data/00-count-loc-all.csv

DATA_DIR="./data"
mkdir -p "$DATA_DIR"

declare -A PROJECTS=(
  #["../codebases/chromium"]="chromium"
  #["../codebases/gitlab"]="gitlab"
  ["../codebases/kubernetes"]="kubernetes"
  ["../codebases/vespa"]="vespa"
)

OUT_SUMMARY="$DATA_DIR/00-count-loc-all.csv"
echo "project,language,filename,file,blank,comment,code" > "$OUT_SUMMARY"

for path in "${!PROJECTS[@]}"
do
  name=${PROJECTS[$path]}
  echo "Running cloc for $name (path: $path)"
  cloc --timeout 0 --csv "$path" | tail -n +2 | sed "s/^/$name,/" >> "$OUT_SUMMARY" || echo "cloc failed for $name" >&2
done

echo "Done. Combined summary: $OUT_SUMMARY"