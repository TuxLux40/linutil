#! /bin/sh
# Script to set global git configuration for username, email, and gpg signing key

# Pre-checks
if ! command -v git >/dev/null 2>&1; then
    printf "Error: git is not installed or not in PATH\n"
    exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
    printf "Error: gpg is not installed or not in PATH\n"
    exit 1
fi

printf "Setting global git username\n"
git config --global user.name "TuxLux40"

# Check if username was set correctly
if [ "$(git config --global user.name)" = "TuxLux40" ]; then
    printf "Username set correctly\n"
else
    printf "Error: Failed to set username\n"
    exit 1
fi

printf "Setting global git email\n"
git config --global user.email "tuxlux40@pm.me"

# Check if email was set correctly
if [ "$(git config --global user.email)" = "tuxlux40@pm.me" ]; then
    printf "Email set correctly\n"
else
    printf "Error: Failed to set email\n"
    exit 1
fi

printf "Setting global git signing key\n"

# Validate signing key exists
if ! gpg --list-keys CE3E8BC6DF4C181B8F7737FB7D3720B9826A757B >/dev/null 2>&1; then
    printf "Error: GPG key not found: CE3E8BC6DF4C181B8F7737FB7D3720B9826A757B\n"
    exit 1
fi

git config --global user.signingkey CE3E8BC6DF4C181B8F7737FB7D3720B9826A757B

# Check if signing key was set correctly
if [ "$(git config --global user.signingkey)" = "CE3E8BC6DF4C181B8F7737FB7D3720B9826A757B" ]; then
    printf "Signing key set correctly\n"
else
    printf "Error: Failed to set signing key\n"
    exit 1
fi

printf "Enabling gpg signing for all commits\n"
git config --global commit.gpgSign true

# Check if gpg signing was enabled correctly
if [ "$(git config --global commit.gpgSign)" = "true" ]; then
    printf "GPG signing enabled correctly\n"
else
    printf "Error: Failed to enable GPG signing\n"
    exit 1
fi
