#!/usr/bin/env bash
set -euo pipefail

# Native cross-compile for aarch64 (Raspberry Pi 3/4/5 with 64-bit Raspberry Pi OS / Ubuntu ARM64).
# Produces dist/linutil-aarch64. No Docker required — uses rustup + aarch64-linux-gnu-gcc.
#
# Usage:
#   ./build-pi.sh                 # just build → dist/linutil-aarch64
#   ./build-pi.sh --release TAG   # build + upload to release TAG (creates it if missing)
#   ./build-pi.sh --release       # build + upload to today's date tag (YY.M.D)

TARGET=aarch64-unknown-linux-gnu
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

# Cross linker (Arch/CachyOS: pacman -S aarch64-linux-gnu-gcc; Debian/Ubuntu: gcc-aarch64-linux-gnu)
if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "ERROR: aarch64-linux-gnu-gcc not found." >&2
    echo "  Arch/CachyOS: sudo pacman -S aarch64-linux-gnu-gcc" >&2
    echo "  Debian/Ubuntu: sudo apt install gcc-aarch64-linux-gnu" >&2
    exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "ERROR: cmake not found." >&2
    echo "  Arch/CachyOS: sudo pacman -S cmake extra-cmake-modules ninja" >&2
    echo "  Debian/Ubuntu: sudo apt install cmake extra-cmake-modules ninja-build" >&2
    exit 1
fi

if ! command -v ninja >/dev/null 2>&1; then
    echo "ERROR: ninja not found." >&2
    echo "  Arch/CachyOS: sudo pacman -S ninja" >&2
    echo "  Debian/Ubuntu: sudo apt install ninja-build" >&2
    exit 1
fi

# Rust target
if ! rustup target list --installed | grep -q "^$TARGET$"; then
    echo "Installing rustup target $TARGET..."
    rustup target add "$TARGET"
fi

echo "Building $TARGET (release, opt-level=z, LTO)..."
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    cargo build --target-dir=build --release --target="$TARGET" --all-features -p linutil_tui

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
    gh release create "$tag" --generate-notes --title "Release $tag"
fi
gh release upload "$tag" "$DIST_DIR/$ASSET" --clobber

echo "Done. Asset available at:"
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "  https://github.com/$repo/releases/download/$tag/$ASSET"
