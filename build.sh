#!/bin/sh
# build.sh -- builds the installer package.
#
#   ./build.sh                       unsigned pkg
#   ./build.sh "Developer ID Installer: Company (TEAMID)"   signed pkg
#
# Output: build/PSPTPluginPermissions-<version>.pkg

set -eu

IDENTIFIER="com.pictureshop.ptpluginperms"
VERSION="1.0"
NAME="PSPTPluginPermissions"
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="${HERE}/build/${NAME}-${VERSION}.pkg"
SIGN_ID="${1:-}"

# Strip extended attributes so the payload carries no AppleDouble junk.
xattr -cr "${HERE}/payload" "${HERE}/scripts" 2>/dev/null || true

mkdir -p "${HERE}/build"
rm -f "$OUT"

chmod 755 "${HERE}/payload/usr/local/libexec/pictureshop/"*.sh
chmod 644 "${HERE}/payload/Library/LaunchDaemons/"*.plist
chmod 644 "${HERE}/payload/Library/LaunchAgents/"*.plist
chmod 755 "${HERE}/scripts/postinstall"

pkgbuild \
    --root "${HERE}/payload" \
    --scripts "${HERE}/scripts" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --ownership recommended \
    --install-location / \
    "$OUT"

if [ -n "$SIGN_ID" ]; then
    productsign --sign "$SIGN_ID" "$OUT" "${OUT}.signed"
    mv -f "${OUT}.signed" "$OUT"
    echo "Signed with: $SIGN_ID"
fi

echo "Built: $OUT"
pkgutil --payload-files "$OUT"
