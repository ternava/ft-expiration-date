#!/usr/bin/env bash
set -euo pipefail

# This script will show the last release info for each of the subject systems
# Usage: ./scripts/00-get-release-info.sh

CODEBASE_DIR="../codebases"

echo "System | Version | Commit | Date"
echo "-------|---------|-------|-----"

# Chromium
if [ -d "$CODEBASE_DIR/chromium" ]
then
    MAJOR=$(grep "MAJOR=" "$CODEBASE_DIR/chromium/chrome/VERSION" 2>/dev/null | cut -d'=' -f2)
    COMMIT=$(cd "$CODEBASE_DIR/chromium" && git rev-parse --short HEAD 2>/dev/null)
    DATE=$(cd "$CODEBASE_DIR/chromium" && git log -1 --format=%ci "$COMMIT" 2>/dev/null | cut -d' ' -f1)
    echo "Chromium | M$MAJOR | $COMMIT | $DATE"
fi

# Kubernetes
if [ -d "$CODEBASE_DIR/kubernetes" ]
then
    TAG=$(cd "$CODEBASE_DIR/kubernetes" && git describe --tags --abbrev=0 2>/dev/null | sed 's/-.*//')
    COMMIT=$(cd "$CODEBASE_DIR/kubernetes" && git rev-parse --short HEAD 2>/dev/null)
    DATE=$(cd "$CODEBASE_DIR/kubernetes" && git log -1 --format=%ci "$COMMIT" 2>/dev/null | cut -d' ' -f1)
    echo "Kubernetes | $TAG | $COMMIT | $DATE"
fi

# GitLab
if [ -d "$CODEBASE_DIR/gitlab" ]
then
    VERSION=$(cat "$CODEBASE_DIR/gitlab/VERSION" 2>/dev/null)
    COMMIT=$(cd "$CODEBASE_DIR/gitlab" && git rev-parse --short HEAD 2>/dev/null)
    DATE=$(cd "$CODEBASE_DIR/gitlab" && git log -1 --format=%ci "$COMMIT" 2>/dev/null | cut -d' ' -f1)
    echo "GitLab | v$VERSION | $COMMIT | $DATE"
fi

# Firefox
# if [ -d "$CODEBASE_DIR/firefox" ]
# then
#     VERSION=$(cat "$CODEBASE_DIR/firefox/browser/config/version.txt" 2>/dev/null)
#     COMMIT=$(cd "$CODEBASE_DIR/firefox" && git rev-parse --short HEAD 2>/dev/null)
#     DATE=$(cd "$CODEBASE_DIR/firefox" && git log -1 --format=%ci "$COMMIT" 2>/dev/null | cut -d' ' -f1)
#     echo "Firefox | v$VERSION | $COMMIT | $DATE"
# fi

# Vespa
if [ -d "$CODEBASE_DIR/vespa" ]
then
    # Vespa might not have version file, so we use git
    TAG=$(cd "$CODEBASE_DIR/vespa" && git describe --tags --abbrev=0 2>/dev/null)
    COMMIT=$(cd "$CODEBASE_DIR/vespa" && git rev-parse --short HEAD 2>/dev/null)
    DATE=$(cd "$CODEBASE_DIR/vespa" && git log -1 --format=%ci "$COMMIT" 2>/dev/null | cut -d' ' -f1)
    echo "Vespa | $TAG | $COMMIT | $DATE"
fi
