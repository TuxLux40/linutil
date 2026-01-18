#!/usr/bin/env sh
install_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    printf '%b %bHomebrew already installed. Skipping install step.%b\n' "${INFO}" "${GREEN}" "${NC}"
  else
    printf '%b %bInstalling Homebrew...%b\n' "${INFO}" "${YELLOW}" "${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      printf '%b %bHomebrew installation failed.%b\n' "${ERROR}" "${RED}" "${NC}"
      return 1
    }
  fi

  if command -v brew >/dev/null 2>&1; then
    BREW_BIN="$(command -v brew)"
  elif [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"
  else
    printf '%b %bbrew binary not found after install attempt.%b\n' "${ERROR}" "${RED}" "${NC}"
    return 1
  fi

  if ! grep -q 'brew shellenv' "$HOME/.bashrc" 2>/dev/null; then
    printf 'eval "%s"\n' "$("${BREW_BIN}" shellenv)" >> "$HOME/.bashrc"
    printf '%b %bAdded brew shellenv to ~/.bashrc%b\n' "${INFO}" "${GREEN}" "${NC}"
  fi
  eval "$("${BREW_BIN}" shellenv)"

  mkdir -p "$HOME/.config/fish"
  FISH_CONFIG="$HOME/.config/fish/config.fish"
  if ! grep -q 'brew shellenv' "$FISH_CONFIG" 2>/dev/null; then
    printf 'eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)\n' >> "$FISH_CONFIG"
    printf '%b %bAdded brew shellenv to fish config.%b\n' "${INFO}" "${GREEN}" "${NC}"
  fi

  printf '%b %bHomebrew ready (bash + fish).%b\n' "${INFO}" "${GREEN}" "${NC}"
}

install_homebrew || printf '%b %bContinuing despite Homebrew issues.%b\n' "${ERROR}" "${RED}" "${NC}"