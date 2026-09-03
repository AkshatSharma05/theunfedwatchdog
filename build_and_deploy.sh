#!/bin/bash

set -e

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/theunfedwatchdog"
PUBLIC_SUBMODULE="$SOURCE_DIR/public"

PRODUCTION_URL="https://akshatsharma05.github.io/"

RESUME_SOURCE="$HOME/Downloads/AKSHAT_SHARMA_RESUME.pdf"
RESUME_DEST="$SOURCE_DIR/static/docs/resume/akshat_sharma_cv.pdf"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

cleanup() {
    if [ -n "${BUILD_DIR:-}" ] && [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi
}

trap cleanup EXIT

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

echo "========================================"
echo "   Hugo Site Build & Deploy"
echo "========================================"
echo

cd "$SCRIPT_DIR"

# ------------------------------------------------------------
# Initialize / update public submodule
# ------------------------------------------------------------

echo "✓ Updating public submodule..."

git submodule update --init --recursive "$PUBLIC_SUBMODULE"

cd "$PUBLIC_SUBMODULE"

# Make sure we are on the deployment branch
git checkout main

# Get latest deployed version
git pull --ff-only origin main

cd "$SOURCE_DIR"

# ------------------------------------------------------------
# Copy resume
# ------------------------------------------------------------

if [ -f "$RESUME_SOURCE" ]; then
    echo "✓ Copying resume..."
    mkdir -p "$(dirname "$RESUME_DEST")"
    cp "$RESUME_SOURCE" "$RESUME_DEST"
else
    echo "⚠ Resume not found:"
    echo "  $RESUME_SOURCE"
    echo "  Keeping existing resume, if present."
fi

# ------------------------------------------------------------
# Build Hugo site
# ------------------------------------------------------------

echo
echo "✓ Building Hugo site..."

# IMPORTANT:
# Do NOT build directly into public/.
# public/ is a Git submodule.
BUILD_DIR="$(mktemp -d)"

hugo \
    --baseURL="$PRODUCTION_URL" \
    --destination="$BUILD_DIR" \
    --minify

# ------------------------------------------------------------
# Sanity checks
# ------------------------------------------------------------

echo
echo "✓ Checking generated URLs..."

if grep -Rni "localhost:1313" "$BUILD_DIR" >/dev/null 2>&1; then
    echo
    echo "ERROR: Generated site contains localhost URLs!"
    echo
    grep -Rni "localhost:1313" "$BUILD_DIR" | head -20
    exit 1
fi

if ! grep -Rni "https://akshatsharma05.github.io" "$BUILD_DIR" >/dev/null 2>&1; then
    echo
    echo "ERROR: Production URL was not found in generated site!"
    exit 1
fi

# ------------------------------------------------------------
# Sync generated site into public submodule
# ------------------------------------------------------------

echo "✓ Syncing generated site..."

rsync -av \
    --delete \
    --exclude='.git' \
    "$BUILD_DIR/" \
    "$PUBLIC_SUBMODULE/"

# ------------------------------------------------------------
# Commit and push public repository
# ------------------------------------------------------------

echo
echo "✓ Updating public repository..."

cd "$PUBLIC_SUBMODULE"

git add .

if git diff-index --quiet HEAD --; then
    echo "  (no changes in public submodule)"
else
    git commit -m "Build: Update site content"
    git push origin main
    echo "  Pushed to public repository"
fi

# ------------------------------------------------------------
# Update parent repository submodule pointer
# ------------------------------------------------------------

echo
echo "✓ Updating parent repository..."

cd "$SCRIPT_DIR"

git add "$PUBLIC_SUBMODULE"

if git diff-index --quiet HEAD --; then
    echo "  (no changes in parent repo)"
else
    git commit -m "Update: Public submodule pointer"
    git push origin main
    echo "  Pushed submodule pointer"
fi

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

echo
echo "========================================"
echo "✓ Deploy Complete!"
echo "========================================"
echo
echo "Site URL:"
echo "  $PRODUCTION_URL"
echo
echo "Resume:"
echo "  ${PRODUCTION_URL}docs/resume/akshat_sharma_cv.pdf"
echo
