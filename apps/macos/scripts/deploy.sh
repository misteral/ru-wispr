#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: deploy.sh <version>"
  echo "Example: deploy.sh 0.9.1"
  exit 1
fi

VERSION="$1"
TAG="v${VERSION}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Deploying dikto ${TAG}"

current=$(grep 'static let version' "${REPO_DIR}/Sources/DiktoLib/Version.swift" | sed 's/.*"\(.*\)".*/\1/')
if [ "$current" != "$VERSION" ]; then
  echo "Error: Version.swift version is ${current}, expected ${VERSION}"
  echo "Update Sources/DiktoLib/Version.swift first."
  exit 1
fi

echo "==> Building release..."
swift build --package-path "${REPO_DIR}" -c release --disable-sandbox

echo "==> Committing, tagging, and pushing main repo..."
git -C "${REPO_DIR}" add -A
git -C "${REPO_DIR}" diff --cached --quiet && echo "Nothing to commit in main repo." || \
  git -C "${REPO_DIR}" commit -m "${TAG}: $(git -C "${REPO_DIR}" log -1 --format=%s)"
git -C "${REPO_DIR}" tag -f "${TAG}"
git -C "${REPO_DIR}" push origin main --tags

echo "==> Generating release notes..."
PREV_TAG=$(git -C "${REPO_DIR}" describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
if [ -n "$PREV_TAG" ]; then
  COMMITS=$(git -C "${REPO_DIR}" log "${PREV_TAG}..HEAD" --pretty=format:"- %s" --no-merges)
else
  COMMITS=$(git -C "${REPO_DIR}" log --pretty=format:"- %s" --no-merges -20)
fi

NOTES=$(claude -p "You are writing release notes for dikto ${TAG}, a local voice dictation app for macOS. Here are the commits since the last release:

${COMMITS}

Write concise GitHub release notes in markdown. Use these sections only if relevant: ### What's New, ### Bug Fixes, ### Other Changes. Use bullet points. Don't include commit hashes. Keep it short and user-facing — skip internal/dev-only changes. End with a one-liner install instruction: Download the latest DMG from GitHub Releases.")

echo "==> Creating GitHub Release..."
gh release create "${TAG}" --repo misteral/dikto --notes "${NOTES}"

echo ""
echo "==> Deployed ${TAG}"
echo "Users can download the DMG from: https://github.com/misteral/dikto/releases/tag/${TAG}"
