#!/usr/bin/env bash
set -euo pipefail

# Local cross-compile for aarch64 (Raspberry Pi 3/4/5 with 64-bit OS),
# producing dist/linutil-aarch64. Optionally uploads it to a GitHub release.
#
# Usage:
#   ./build-pi.sh                 # just build → dist/linutil-aarch64
#   ./build-pi.sh --release TAG   # build + upload to release TAG (creates it if missing)
#   ./build-pi.sh --release       # build + upload to today's date tag (YY.M.D)

TARGET=aarch64-unknown-linux-musl
ASSET=linutil-aarch64
DIST_DIR=dist

do_release=false
tag=""

while [ $# -gt 0 ]; do
    case "$1" in
        --release)
            do_release=true
            if [ $# -ge 2 ] && [ "${2#--}" = "$2" ]; then
                tag="$2"
                shift
            fi
            ;;
        -h|--help)
            sed -n '3,12p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
    shift
done

if ! command -v cross >/dev/null 2>&1; then
    echo "cross not found — installing via cargo..."
    cargo install cross --locked
fi

if ! docker info >/dev/null 2>&1 && ! podman info >/dev/null 2>&1; then
    echo "ERROR: neither docker nor podman daemon reachable — cross needs a container engine." >&2
    exit 1
fi

echo "Building $TARGET (this uses a Docker container, first run pulls ~500MB)..."
cross build --target-dir=build --release --target="$TARGET" --all-features

mkdir -p "$DIST_DIR"
cp "build/$TARGET/release/linutil" "$DIST_DIR/$ASSET"
chmod +x "$DIST_DIR/$ASSET"

echo
echo "Built: $DIST_DIR/$ASSET"
file "$DIST_DIR/$ASSET" || true
ls -lh "$DIST_DIR/$ASSET"

if [ "$do_release" = false ]; then
    exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not found — install it to use --release." >&2
    exit 1
fi

if [ -z "$tag" ]; then
    tag=$(date +"%y.%-m.%-d")
fi

echo
echo "Uploading $ASSET to release $tag..."
if ! gh release view "$tag" >/dev/null 2>&1; then
    echo "Release $tag does not exist — creating it."
    gh release create "$tag" --prerelease --generate-notes --title "Pre-Release $tag"
fi
gh release upload "$tag" "$DIST_DIR/$ASSET" --clobber

echo "Done. Asset available at:"
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "  https://github.com/$repo/releases/download/$tag/$ASSET"
