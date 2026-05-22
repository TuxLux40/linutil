#!/bin/sh -e

# One-shot installer for the precompiled aarch64 binary from this fork's GitHub Releases.
# Intended for low-powered ARM devices (e.g. Raspberry Pi 3/4/5 running a 64-bit OS)
# where building from source via cargo takes a very long time.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tuxlux40/linutil/main/install-pi.sh | sh
#
# Override the repo or install location with env vars:
#   LINUTIL_REPO=tuxlux40/linutil
#   LINUTIL_INSTALL_DIR=/usr/local/bin
{
rc=$(printf '\033[0m')
red=$(printf '\033[0;31m')
green=$(printf '\033[0;32m')

check() {
    exit_code=$1
    message=$2

    if [ "$exit_code" -ne 0 ]; then
        printf '%sERROR: %s%s\n' "$red" "$message" "$rc"
        exit 1
    fi
}

REPO=${LINUTIL_REPO:-tuxlux40/linutil}
INSTALL_DIR=${LINUTIL_INSTALL_DIR:-/usr/local/bin}

arch=$(uname -m)
case "$arch" in
    aarch64|arm64) asset="linutil-aarch64" ;;
    x86_64|amd64)  asset="linutil" ;;
    *) check 1 "Unsupported architecture: $arch (this installer only ships precompiled aarch64 and x86_64 binaries)" ;;
esac

url="https://github.com/${REPO}/releases/latest/download/${asset}"

printf 'Downloading %s from %s\n' "$asset" "$url"

tmp=$(mktemp)
check $? "Creating temporary file"

curl -fL --progress-bar "$url" -o "$tmp"
check $? "Downloading $asset"

chmod +x "$tmp"
check $? "Marking binary as executable"

if [ -w "$INSTALL_DIR" ]; then
    mv "$tmp" "$INSTALL_DIR/linutil"
else
    sudo mv "$tmp" "$INSTALL_DIR/linutil"
fi
check $? "Installing to $INSTALL_DIR/linutil"

printf '%slinutil installed to %s/linutil%s\n' "$green" "$INSTALL_DIR" "$rc"
printf 'Run it with: sudo linutil\n'
} # End of wrapping
