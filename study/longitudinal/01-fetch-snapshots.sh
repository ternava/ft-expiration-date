#!/usr/bin/env bash
set -euo pipefail

# Downloads the toggle definition files needed for the longitudinal analysis into raw/.
#
# For each system we download only the files in which toggles and their deadlines are
# declared (the same files the T0 scripts in ../scripts read), at
#   - T0, the commits analysed in Table 1 of the paper,
#   - T1, a follow-up snapshot taken on 31 October 2026,
#   - earlier points: every Chromium milestone branch point since M80, every GitLab monthly
#     release since 17.0, every Kubernetes minor release since v1.32, and every commit that
#     changed Vespa's Flags.java or PermanentFlags.java.
# We also download the GitLab merge requests labelled automation:feature-flag-removal,
# which are opened by GitLab's DeleteOldFeatureFlags keep.
#
# You only need this script to rebuild raw/ from scratch, since raw.tar.xz already holds
# its output. Files that already exist are skipped, so the script can be stopped and
# restarted. Steps can be run alone, e.g. ./01-fetch-snapshots.sh kubernetes gitlab
# Only data up to T1 is downloaded, but the state of a merge request (open, merged, closed)
# is the one at download time.
#
# Requires: curl, jq, base64, GNU date, and a logged-in GitHub CLI (gh)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW="${RAW:-$HERE/raw}"
JOBS="${JOBS:-8}"
export RAW

T0_CHROMIUM=54e2a848c65e498cd112607e9133e9797d1e7fa8
T0_GITLAB=f3114f736b1e28230f1f8079a03e3c65896cb5b4
T0_KUBERNETES=c180d6762d7ac5059d9b50457cafb0d7f4cf74a9
T0_VESPA=f2f0d37afd1d889e33a12f82fbf58809dbdef391
T1_CHROMIUM=78971efe8c231919e6191a3460f7a816062ed874
T1_GITLAB=bf4a74a13e89f2d270825e6e1f64a2cab9c725e7
T1_KUBERNETES=3c690c189e5d367715dbd056a5c2009a476c8d77
T1_VESPA=44bcb9564ac1b35512b53a41c4c97880299aa5f1

K8S_FILES=(
    pkg/features/kube_features.go
    staging/src/k8s.io/apiserver/pkg/features/kube_features.go
    staging/src/k8s.io/component-base/logs/api/v1/kube_features.go
    staging/src/k8s.io/apiextensions-apiserver/pkg/features/kube_features.go
    staging/src/k8s.io/controller-manager/pkg/features/kube_features.go
    staging/src/k8s.io/component-base/zpages/features/kube_features.go
    test/e2e/framework/internal/unittests/features/kube_features.go
)
K8S_TAGS=(v1.32.0 v1.33.0 v1.34.0 v1.35.0 v1.36.0 v1.37.0)
VESPA_FLAGS=flags/src/main/java/com/yahoo/vespa/flags/Flags.java
VESPA_PERMANENT=flags/src/main/java/com/yahoo/vespa/flags/PermanentFlags.java
GITLAB_API=https://gitlab.com/api/v4/projects/278964

# Monthly releases from 17.0 (May 2024) to 19.5 (October 2026), the last one before T1
GITLAB_TAGS=()
for m in $(seq 0 11); do GITLAB_TAGS+=("v17.$m.0-ee"); done
for m in $(seq 0 11); do GITLAB_TAGS+=("v18.$m.0-ee"); done
for m in $(seq 0 5); do GITLAB_TAGS+=("v19.$m.0-ee"); done

# Downloads $1 to $2. A missing file (HTTP 404) is recorded as $2.404 and not retried.
fetch() {
    local url="$1" out="$2" code
    [[ -e "$out" || -e "$out.404" ]] && return 0
    mkdir -p "$(dirname "$out")"
    code="$(curl -sSL --retry 5 --retry-delay 2 -A ft-expiration-study -o "$out.part" -w '%{http_code}' "$url" || true)"
    if [[ "$code" == 200 ]]; then
        mv "$out.part" "$out"
    elif [[ "$code" == 404 ]]; then
        rm -f "$out.part"
        : > "$out.404"
    else
        rm -f "$out.part"
        echo "failed ($code): $url" >&2
        return 1
    fi
}
export -f fetch

# Gitiles serves raw files base64-encoded with ?format=TEXT
fetch_gitiles() {
    local url="$1" out="$2"
    [[ -e "$out" ]] && return 0
    fetch "$url?format=TEXT" "$out.b64" || return 1
    [[ -e "$out.b64" ]] && base64 -d "$out.b64" > "$out" && rm "$out.b64"
    return 0
}
export -f fetch_gitiles

fetch_chromium() {
    local d="$RAW/chromium" src=https://chromium.googlesource.com/chromium/src/+
    mkdir -p "$d"
    if [[ ! -e "$d/refs.json" ]]; then
        curl -sSL --retry 5 'https://chromiumdash.appspot.com/fetch_milestones?only_branched=true' |
            jq --arg t0 "$T0_CHROMIUM" --arg t1 "$T1_CHROMIUM" \
               '[.[] | select(.milestone >= 80 and .milestone <= 158) | {key: "M\(.milestone)", value: .chromium_main_branch_hash}]
                | from_entries + {T0: $t0, T1: $t1}' > "$d/refs.json"
    fi
    jq -r 'to_entries[] | "\(.key) \(.value)"' "$d/refs.json" |
        while read -r label sha; do
            fetch_gitiles "$src/$sha/chrome/browser/flag-metadata.json" "$d/$label.json"
            fetch_gitiles "$src/$sha/chrome/VERSION" "$d/$label.VERSION"
        done
}

fetch_gitlab() {
    local d="$RAW/gitlab" label ref page batch
    mkdir -p "$d"
    for label in "${GITLAB_TAGS[@]}" T0 T1; do
        case "$label" in T0) ref=$T0_GITLAB ;; T1) ref=$T1_GITLAB ;; *) ref=$label ;; esac
        fetch "https://gitlab.com/gitlab-org/gitlab/-/archive/$ref/gitlab-$ref.tar.gz?path=config/feature_flags" \
              "$d/$label.tar.gz"
    done
    # EE flag definitions, only to check whether a flag moved from config/ to ee/config/
    fetch "https://gitlab.com/gitlab-org/gitlab/-/archive/$T0_GITLAB/gitlab-$T0_GITLAB.tar.gz?path=ee/config/feature_flags" \
          "$d/ee-T0.tar.gz"
    fetch "https://gitlab.com/gitlab-org/gitlab/-/archive/$T1_GITLAB/gitlab-$T1_GITLAB.tar.gz?path=ee/config/feature_flags" \
          "$d/ee-T1.tar.gz"

    if [[ ! -e "$d/removal-mrs.json" ]]; then
        page=1
        : > "$d/removal-mrs.ndjson"
        while :; do
            batch="$(curl -sSL --retry 5 "$GITLAB_API/merge_requests?labels=automation:feature-flag-removal&state=all&created_before=2026-11-01T00:00:00Z&per_page=100&page=$page")"
            [[ "$(jq length <<< "$batch")" == 0 ]] && break
            jq -c '.[]' <<< "$batch" >> "$d/removal-mrs.ndjson"
            page=$((page + 1))
        done
        jq -s . "$d/removal-mrs.ndjson" > "$d/removal-mrs.json"
        rm "$d/removal-mrs.ndjson"
    fi
}

fetch_kubernetes() {
    local d="$RAW/kubernetes" label ref f
    for label in "${K8S_TAGS[@]}" T0 T1; do
        case "$label" in T0) ref=$T0_KUBERNETES ;; T1) ref=$T1_KUBERNETES ;; *) ref=$label ;; esac
        for f in "${K8S_FILES[@]}"; do
            fetch "https://raw.githubusercontent.com/kubernetes/kubernetes/$ref/$f" "$d/$label/${f//\//__}"
        done
    done
}

fetch_vespa() {
    local d="$RAW/vespa" name path
    mkdir -p "$d"
    for name in flags permanent; do
        [[ $name == flags ]] && path=$VESPA_FLAGS || path=$VESPA_PERMANENT
        if [[ ! -e "$d/$name-commits.json" ]]; then
            gh api --paginate "repos/vespa-engine/vespa/commits?path=$path&until=2026-11-01T00:00:00Z&per_page=100" \
                --jq '.[] | {sha: .sha, date: .commit.committer.date}' | jq -s . > "$d/$name-commits.json"
        fi
        { jq -r '.[].sha' "$d/$name-commits.json"; echo "$T0_VESPA"; echo "$T1_VESPA"; } |
            xargs -P "$JOBS" -I{} bash -c 'fetch "https://raw.githubusercontent.com/vespa-engine/vespa/{}/'"$path"'" "'"$d/$name"'/{}.java"'
    done
}

# Commit date of every snapshot, used to order the snapshots and to define time windows
fetch_dates() {
    local out="$RAW/dates.json" tmp label sha tag date
    tmp="$(mktemp)"
    [[ -e "$out" ]] && cp "$out" "$tmp" || echo '{}' > "$tmp"
    add() { jq --arg k "$1" --arg v "$2" '.[$k] //= $v' "$tmp" > "$tmp.new" && mv "$tmp.new" "$tmp"; }
    has() { jq -e --arg k "$1" 'has($k)' "$tmp" > /dev/null; }

    jq -r 'to_entries[] | "\(.key) \(.value)"' "$RAW/chromium/refs.json" |
        while read -r label sha; do
            has "chromium:$label" && continue
            # Gitiles prefixes its JSON with )]}' on the first line, and sometimes answers
            # with an error page under load, so we retry until the answer parses
            for _ in 1 2 3 4 5; do
                date="$(curl -sSL --retry 5 "https://chromium.googlesource.com/chromium/src/+/$sha?format=JSON" |
                        tail -n +2 | jq -r '.committer.time' 2>/dev/null)" && break
                sleep 3
            done
            add "chromium:$label" "$(date -d "$date" +%F)"
        done
    for tag in "${GITLAB_TAGS[@]}"; do
        has "gitlab:$tag" && continue
        add "gitlab:$tag" "$(curl -sSL --retry 5 "$GITLAB_API/repository/tags/$tag" | jq -r '.commit.committed_date[:10]')"
    done
    for tag in "${K8S_TAGS[@]}"; do
        has "kubernetes:$tag" && continue
        add "kubernetes:$tag" "$(gh api "repos/kubernetes/kubernetes/commits/$tag" --jq '.commit.committer.date[:10]')"
    done
    jq -S '. + {"chromium:T0": "2025-12-14", "gitlab:T0": "2026-02-26", "kubernetes:T0": "2025-12-13",
                "vespa:T0": "2025-12-22", "chromium:T1": "2026-10-31", "gitlab:T1": "2026-10-31",
                "kubernetes:T1": "2026-10-31", "vespa:T1": "2026-10-31"}' "$tmp" > "$out"
    rm "$tmp"
}

steps=("$@")
[[ ${#steps[@]} -eq 0 ]] && steps=(kubernetes gitlab chromium vespa dates)
for step in "${steps[@]}"; do
    SECONDS=0
    "fetch_$step"
    echo "$step: done in ${SECONDS}s"
done
