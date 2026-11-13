#!/usr/bin/env bash
set -euo pipefail

# Runs the T0 extraction scripts of ../scripts on every downloaded snapshot in raw/.
# Each snapshot is laid out as a minimal checkout that contains only the files the
# scripts read, so the scripts run unchanged. Output: one CSV per snapshot in snapshots/.
#
# Usage: ./02-extract-snapshots.sh
# Requires: bash, jq, awk, GNU grep, tar, xz

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
RAW="$HERE/raw"
OUT="$HERE/snapshots"
JOBS="${JOBS:-$(nproc)}"

if [[ ! -d "$RAW" ]]; then
    tar -xJf "$HERE/raw.tar.xz" -C "$HERE"
fi
mkdir -p "$OUT"/{chromium,gitlab,kubernetes,vespa/flags,vespa/permanent}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- Chromium
for json in "$RAW"/chromium/*.json; do
    label="$(basename "$json" .json)"
    [[ "$label" == refs ]] && continue
    dir="$TMP/chromium/$label"
    mkdir -p "$dir/chrome/browser"
    cp "$json" "$dir/chrome/browser/flag-metadata.json"
    "$SCRIPTS/01-extract-feature-flags-chromium.sh" "$dir" "$OUT/chromium/$label.csv" >/dev/null
done
echo "Chromium: $(ls "$OUT/chromium" | wc -l) snapshots"

# ------------------------------------------------------------------ GitLab
# The archives hold config/feature_flags (and ee/config/feature_flags for ee-T0, ee-T1).
for tgz in "$RAW"/gitlab/*.tar.gz; do
    label="$(basename "$tgz" .tar.gz)"
    dir="$TMP/gitlab/$label"
    mkdir -p "$dir"
    tar -xzf "$tgz" -C "$dir" --strip-components=1
    [[ "$label" == ee-* ]] && dir="$dir/ee"
    # Run from inside the checkout, so that definition_file is a path relative to it
    (cd "$dir" && "$SCRIPTS/01-extract-feature-flags-gitlab.sh" . "$OUT/gitlab/$label.csv" >/dev/null)
done
echo "GitLab: $(ls "$OUT/gitlab" | wc -l) snapshots"

# -------------------------------------------------------------- Kubernetes
# Files are stored as path__to__kube_features.go; *.404 marks a file absent at that version.
for snap in "$RAW"/kubernetes/*/; do
    label="$(basename "$snap")"
    dir="$TMP/kubernetes/$label"
    for f in "$snap"*.go; do
        rel="$(basename "$f" | sed 's/__/\//g')"
        mkdir -p "$dir/$(dirname "$rel")"
        cp "$f" "$dir/$rel"
    done
    "$SCRIPTS/01-extract-feature-gates-kubernetes.sh" "$dir" "$OUT/kubernetes/$label.csv" >/dev/null
done
echo "Kubernetes: $(ls "$OUT/kubernetes" | wc -l) snapshots"

# ------------------------------------------------------------------- Vespa
# One version per commit that changed Flags.java or PermanentFlags.java. The other file
# is left empty, so each CSV holds the flags of one file at one commit.
vespa_one() {
    local kind="$1" java="$2" sha dir flags
    sha="$(basename "$java" .java)"
    dir="$TMP/vespa/$kind/$sha"
    flags="$dir/flags/src/main/java/com/yahoo/vespa/flags"
    mkdir -p "$flags"
    : > "$flags/Flags.java"
    : > "$flags/PermanentFlags.java"
    if [[ "$kind" == flags ]]; then
        cp "$java" "$flags/Flags.java"
    else
        cp "$java" "$flags/PermanentFlags.java"
    fi
    "$SCRIPTS/01-extract-feature-flags-vespa.sh" "$dir" "$OUT/vespa/$kind/$sha.csv" >/dev/null
    rm -rf "$dir"
}
export -f vespa_one
export SCRIPTS OUT TMP
for kind in flags permanent; do
    find "$RAW/vespa/$kind" -name '*.java' -print0 |
        xargs -0 -P "$JOBS" -I{} bash -c 'vespa_one "$1" "$2"' _ "$kind" {}
    echo "Vespa $kind: $(ls "$OUT/vespa/$kind" | wc -l) versions"
done
cp "$RAW"/vespa/{flags,permanent}-commits.json "$OUT/vespa/"
cp "$RAW/dates.json" "$OUT/"
cp "$RAW/gitlab/removal-mrs.json" "$OUT/gitlab/"
