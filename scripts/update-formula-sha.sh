#!/bin/bash
#
# Updates the Homebrew formula SHA256 after creating a new git tag.
# Usage: ./scripts/update-formula-sha.sh v1.0.0
#

set -euo pipefail

TAG="${1:?Usage: $0 <tag, e.g. v1.0.0>}"
REPO="shyamalschandra/Monitor-Keyboard-Fix"
FORMULA="Formula/monitor-keyboard-fix.rb"

echo "Fetching source tarball for tag ${TAG}..."
URL="https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz"
SHA256=$(curl -sL "$URL" | shasum -a 256 | cut -d ' ' -f 1)

if [[ -z "$SHA256" || "$SHA256" == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]]; then
    echo "ERROR: Could not download tarball or empty file. Is the tag pushed?"
    echo "URL: $URL"
    exit 1
fi

echo "SHA256: $SHA256"

# Update URL version
VERSION="${TAG#v}"
sed -i '' "s|archive/refs/tags/v[^\"]*\.tar\.gz|archive/refs/tags/${TAG}.tar.gz|" "$FORMULA"

# Update SHA256
sed -i '' "s|sha256 \"[^\"]*\"|sha256 \"${SHA256}\"|" "$FORMULA"

echo "Updated ${FORMULA}:"
grep -E '(url|sha256)' "$FORMULA" | head -2
echo ""
echo "Now commit and push the formula update."
