#!/usr/bin/env bash
#
# Release helper — builds a release pry-mcp, signs it with Developer ID,
# notarizes, and produces a ready-to-upload archive.
#
# Requires:
#   - DEVELOPER_ID_APPLICATION env var (e.g. "Developer ID Application: NAME (TEAMID)")
#   - APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD for notarization
#
# Usage:
#   ./scripts/release.sh v0.1.0
#
# Outputs:
#   dist/pry-mcp-<version>-arm64.tar.gz
#   dist/SHA256SUMS
#
# After success:
#   1. Upload the archive as a GitHub release asset.
#   2. Update HomebrewFormula/pry-mcp.rb with the new version + sha256.
#   3. Push the formula update to the tap repo.

set -euo pipefail

VERSION="${1:?usage: $0 <vX.Y.Z>}"
ARCH="arm64"
STAGE="dist"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "DEVELOPER_ID_APPLICATION not set — will produce an unsigned build."
    SIGN=0
else
    SIGN=1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "==> swift build -c release --product pry-mcp"
swift build -c release --product pry-mcp

cp .build/release/pry-mcp "$STAGE/pry-mcp"
chmod +x "$STAGE/pry-mcp"

if [[ "$SIGN" == "1" ]]; then
    echo "==> Codesigning with Developer ID"
    codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp --options runtime "$STAGE/pry-mcp"
    codesign --verify --strict --verbose=2 "$STAGE/pry-mcp"
fi

ARCHIVE="pry-mcp-${VERSION}-${ARCH}.tar.gz"
echo "==> Packing $ARCHIVE"
tar -czf "$STAGE/$ARCHIVE" -C "$STAGE" pry-mcp

if [[ "$SIGN" == "1" && -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    echo "==> Submitting for notarization"
    xcrun notarytool submit "$STAGE/$ARCHIVE" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
fi

(cd "$STAGE" && shasum -a 256 "$ARCHIVE" > SHA256SUMS)
cat "$STAGE/SHA256SUMS"
echo
echo "==> Done. Archive: $STAGE/$ARCHIVE"
