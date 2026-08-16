#!/bin/sh
# Recreate vendor/proxychains-ng from the latest upstream tag and apply
# the LiveContainer-specific patch.
#
# Usage (from the project root):
#   ./scripts/setup.sh
set -eu

PROXYCHAINS_NG_REPO="${PROXYCHAINS_NG_REPO:-https://github.com/rofl0r/proxychains-ng}"
PROXYCHAINS_NG_TAG="${PROXYCHAINS_NG_TAG:-v4.17}"

cd "$(dirname "$0")/.."

rm -rf vendor/proxychains-ng
git clone --depth 1 --branch "$PROXYCHAINS_NG_TAG" "$PROXYCHAINS_NG_REPO" vendor/proxychains-ng
rm -rf vendor/proxychains-ng/.git
patch -p1 < patches/livecontainer.patch

echo "vendor/proxychains-ng is ready ($PROXYCHAINS_NG_TAG + LiveContainer patch)"
