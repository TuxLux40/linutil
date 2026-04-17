#!/bin/sh -e
# shellcheck disable=SC2086

. ../common-script.sh

installWithPackager() {
    pkg="$1"
    case "$PACKAGER" in
        pacman)
            "$AUR_HELPER" -S --needed --noconfirm "$pkg"
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg"
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" -y install "$pkg"
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install "$pkg"
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add "$pkg"
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy "$pkg"
            ;;
        eopkg)
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg"
            ;;
        *)
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg"
            ;;
    esac
}

tryInstallAny() {
    for pkg in "$@"; do
        if installWithPackager "$pkg" >/dev/null 2>&1; then
            printf "%b\n" "${GREEN}Installed: ${pkg}${RC}"
            return 0
        fi
    done
    return 1
}

ensureTool() {
    tool="$1"
    shift

    if command_exists "$tool"; then
        printf "%b\n" "${CYAN}${tool} is already installed.${RC}"
        return 0
    fi

    if ! tryInstallAny "$@"; then
        printf "%b\n" "${YELLOW}Could not install ${tool} from repositories.${RC}"
        return 1
    fi

    if command_exists "$tool"; then
        printf "%b\n" "${GREEN}${tool} is now available.${RC}"
        return 0
    fi

    return 0
}

installExtraDevTools() {
    printf "%b\n" "${YELLOW}Installing extended developer toolchain...${RC}"

    # Build and toolchain basics
    ensureTool gcc gcc
    ensureTool g++ g++ gcc-c++
    ensureTool ld binutils
    ensureTool pkg-config pkg-config pkgconf
    ensureTool ninja ninja ninja-build
    ensureTool meson meson
    ensureTool autoconf autoconf
    ensureTool automake automake
    ensureTool libtool libtool
    ensureTool m4 m4
    ensureTool patch patch
    ensureTool gdb gdb
    ensureTool ccache ccache

    # LLVM/Clang family
    ensureTool clang clang
    ensureTool lld lld

    # Language ecosystems
    ensureTool python3 python3
    ensureTool pip3 python3-pip py3-pip
    ensureTool pipx pipx
    ensureTool node nodejs
    ensureTool npm npm
    ensureTool java default-jdk openjdk-21-jdk openjdk-17-jdk java-21-openjdk java-17-openjdk java-21-openjdk-devel java-17-openjdk-devel

    # Rust tooling (install rustup if available, otherwise fallback to rust/cargo packages)
    if ! command_exists cargo; then
        if ! tryInstallAny rustup rustup-init rust cargo; then
            printf "%b\n" "${YELLOW}Could not install Rust tooling from repositories.${RC}"
        fi
    else
        printf "%b\n" "${CYAN}cargo is already installed.${RC}"
    fi

    # Go tooling
    ensureTool go go golang golang-go

    # Scripting and linting helpers
    ensureTool shellcheck shellcheck
    ensureTool shfmt shfmt

    # Protocol Buffers compiler
    ensureTool protoc protobuf-compiler protobuf

    # Python project manager (uv)
    if ! command_exists uv; then
        if ! tryInstallAny uv python-uv; then
            printf "%b\n" "${YELLOW}uv package not found in repos, installing via upstream installer...${RC}"
            curl -LsSf https://astral.sh/uv/install.sh | sh
            export PATH="$HOME/.local/bin:$PATH"
        fi
    else
        printf "%b\n" "${CYAN}uv is already installed.${RC}"
    fi

    # Venv support package names vary heavily by distro.
    tryInstallAny python3-venv python3-virtualenv py3-virtualenv >/dev/null 2>&1 || true
}

installDepend() {
    ## Check for dependencies.
    BASE_DEPENDENCIES='tar tree multitail trash-cli unzip cmake make jq'
    DEPENDENCIES="$BASE_DEPENDENCIES tldr"
    printf "%b\n" "${YELLOW}Installing dependencies...${RC}"
    case "$PACKAGER" in
        pacman)
            # CachyOS commonly ships tealdeer, which conflicts with tldr.
            DEPENDENCIES="$BASE_DEPENDENCIES tealdeer"
            if ! grep -q "^\s*\[multilib\]" /etc/pacman.conf; then
                echo "[multilib]" | "$ESCALATION_TOOL" tee -a /etc/pacman.conf
                echo "Include = /etc/pacman.d/mirrorlist" | "$ESCALATION_TOOL" tee -a /etc/pacman.conf
                "$ESCALATION_TOOL" "$PACKAGER" -Syu
            else
                printf "%b\n" "${GREEN}Multilib is already enabled.${RC}"
            fi
            "$AUR_HELPER" -S --needed --noconfirm $DEPENDENCIES
            ;;
        apt-get|nala)
            COMPILEDEPS='build-essential'
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" dpkg --add-architecture i386
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y $DEPENDENCIES $COMPILEDEPS
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" update -y
            if ! "$ESCALATION_TOOL" "$PACKAGER" config-manager --enable powertools 2>/dev/null; then
                "$ESCALATION_TOOL" "$PACKAGER" config-manager --enable crb 2>/dev/null || true
            fi
            "$ESCALATION_TOOL" "$PACKAGER" -y install $DEPENDENCIES
            if ! "$ESCALATION_TOOL" "$PACKAGER" -y group install "Development Tools" 2>/dev/null; then
                "$ESCALATION_TOOL" "$PACKAGER" -y group install development-tools
            fi
            "$ESCALATION_TOOL" "$PACKAGER" -y install glibc-devel.i686 libgcc.i686
            ;;
        zypper)
            COMPILEDEPS='patterns-devel-base-devel_basis'
            "$ESCALATION_TOOL" "$PACKAGER" refresh 
            "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install $COMPILEDEPS
            "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install tar tree multitail unzip cmake make jq libgcc_s1-gcc7-32bit glibc-devel-32bit
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add build-base multitail tar tree trash-cli unzip cmake jq
            ;;
        xbps-install)
            COMPILEDEPS='base-devel'
            "$ESCALATION_TOOL" "$PACKAGER" -Sy $DEPENDENCIES $COMPILEDEPS
            "$ESCALATION_TOOL" "$PACKAGER" -Sy void-repo-multilib
            "$ESCALATION_TOOL" "$PACKAGER" -Sy glibc-32bit gcc-multilib
            ;;
        eopkg)
            COMPILEDEPS='-c system.devel'
            "$ESCALATION_TOOL" "$PACKAGER" update-repo
            "$ESCALATION_TOOL" "$PACKAGER" install -y tar tree unzip cmake make jq
            "$ESCALATION_TOOL" "$PACKAGER" install -y $COMPILEDEPS
            ;;
        *)
            "$ESCALATION_TOOL" "$PACKAGER" install -y $DEPENDENCIES
            ;;
    esac
}

checkEnv
checkAURHelper
checkEscalationTool
installDepend
installExtraDevTools
