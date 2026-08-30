#!/bin/bash
# Automated Hugo build and deployment script
# This script handles the entire process of building and deploying your site

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/theunfedwatchdog"
PUBLIC_SUBMODULE="$SOURCE_DIR/public"
PRODUCTION_URL="https://akshatsharma05.github.io/"

echo "=========================================="
echo "Hugo Site Build & Deploy"
echo "=========================================="

# Step 0: Ensure submodule is properly initialized
echo "✓ Ensuring submodule is initialized..."
cd "$SCRIPT_DIR"
git submodule update --init --recursive theunfedwatchdog/public 2>/dev/null || true
cd "$PUBLIC_SUBMODULE"
git checkout main 2>/dev/null || true
git pull origin main 2>/dev/null || true

# Step 1: Update CV from Downloads if it exists
if [ -f "$HOME/Downloads/AKSHAT_SHARMA_RESUME.pdf" ]; then
    echo "✓ Updating CV from Downloads..."
    cp "$HOME/Downloads/AKSHAT_SHARMA_RESUME.pdf" "$SOURCE_DIR/static/docs/resume/akshat_sharma_cv.pdf"
else
    echo "⚠ No CV found in ~/Downloads/AKSHAT_SHARMA_RESUME.pdf"
fi

# Step 2: Clean and build Hugo
echo "✓ Building Hugo site..."
cd "$SOURCE_DIR"
rm -rf public
hugo --baseURL="$PRODUCTION_URL"

# Step 3: Sync to public submodule
echo "✓ Syncing to public submodule..."
# Use rsync but exclude .git files to avoid corrupting submodule
rsync -av "$SOURCE_DIR/public/" "$PUBLIC_SUBMODULE/" --delete --exclude='.git'

# Step 4: Commit and push public submodule
echo "✓ Committing public submodule..."
cd "$PUBLIC_SUBMODULE"

# Explicitly add files (ignore parent repo's submodule config)
git add . 2>/dev/null || true

if git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "  (no changes in public submodule)"
else
    git commit -m "Build: Update site content" 2>/dev/null || true
    git push origin main 2>/dev/null || true
    echo "  Pushed to public submodule"
fi

# Step 5: Update parent repo submodule pointer
echo "✓ Updating parent repo..."
cd "$SCRIPT_DIR"
git add theunfedwatchdog/public
if git diff-index --quiet HEAD --; then
    echo "  (no changes in parent repo)"
else
    git commit -m "Update: Public submodule pointer"
    git push origin main
    echo "  Pushed to source repo"
fi

echo ""
echo "=========================================="
echo "✓ Deploy Complete!"
echo "=========================================="
echo "Site URL: $PRODUCTION_URL"
