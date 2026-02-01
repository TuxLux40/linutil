#! /bin/sh
# Sourced from the official Atuin installation script: https://github.com/atuinsh/atuin/blob/main/install.sh

curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

sleep 1

printf '\n%bImporting history to Atuin...%b\n' "${GREEN}" "${NC}"
atuin import auto
printf '%bAtuin installation and history import complete.%b\n' "${GREEN}" "${NC}"

printf '%bYou may need to restart your terminal or source your shell configuration to start using Atuin.%b\n' "${YELLOW}" "${NC}"

sleep 1