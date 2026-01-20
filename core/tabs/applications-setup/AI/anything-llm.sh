#!/bin/sh -e

# UNTESTED!
# AnythingLLM bare-metal installer
# Clones, builds, and prepares services from source as documented in BARE_METAL.md

. ../common-script.sh

REPO_URL="https://github.com/Mintplex-Labs/anything-llm.git"
DEFAULT_INSTALL_DIR="$HOME/anything-llm"
DEFAULT_STORAGE_DIR="$HOME/anything-llm-storage"
MIN_NODE_MAJOR=18

INSTALL_DIR="$DEFAULT_INSTALL_DIR"
STORAGE_DIR="$DEFAULT_STORAGE_DIR"

assert_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        printf "%b\n" "${RED}Bitte nicht als root ausführen.${RC}"
        exit 1
    fi
}

need_cmd() {
    if ! command_exists "$1"; then
        printf "%b\n" "${RED}Fehlende Abhängigkeit: $1${RC}"
        return 1
    fi
}

ensure_node() {
    if command_exists node; then
        major=$(node -v | sed 's/^v//' | cut -d'.' -f1)
        if [ "$major" -lt "$MIN_NODE_MAJOR" ]; then
            printf "%b\n" "${RED}Node >= $MIN_NODE_MAJOR benötigt (gefunden $(node -v)).${RC}"
        else
            return 0
        fi
    fi

    printf "%b\n" "${YELLOW}Installiere Node.js über Paketmanager...${RC}"
    case "$PACKAGER" in
        pacman) "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm nodejs npm ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y nodejs npm
            ;;
        dnf) "$ESCALATION_TOOL" "$PACKAGER" install -y nodejs npm ;;
        zypper) "$ESCALATION_TOOL" "$PACKAGER" install -y nodejs npm ;;
        apk) "$ESCALATION_TOOL" "$PACKAGER" add nodejs npm ;;
        xbps-install) "$ESCALATION_TOOL" "$PACKAGER" -Sy nodejs npm ;;
        *) printf "%b\n" "${RED}Unbekannter Paketmanager: $PACKAGER${RC}"; exit 1 ;;
    esac

    need_cmd node || exit 1
}

ensure_yarn() {
    if command_exists yarn; then
        return 0
    fi
    need_cmd npm || exit 1
    printf "%b\n" "${YELLOW}Installiere Yarn global...${RC}"
    npm install -g yarn
    need_cmd yarn || exit 1
}

ensure_git() {
    if command_exists git; then
        return 0
    fi
    printf "%b\n" "${YELLOW}Installiere git...${RC}"
    case "$PACKAGER" in
        pacman) "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm git ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y git
            ;;
        dnf) "$ESCALATION_TOOL" "$PACKAGER" install -y git ;;
        zypper) "$ESCALATION_TOOL" "$PACKAGER" install -y git ;;
        apk) "$ESCALATION_TOOL" "$PACKAGER" add git ;;
        xbps-install) "$ESCALATION_TOOL" "$PACKAGER" -Sy git ;;
        *) printf "%b\n" "${RED}Unbekannter Paketmanager: $PACKAGER${RC}"; exit 1 ;;
    esac
}

prompt_paths() {
    printf "%b" "${GREEN}Installationspfad [${DEFAULT_INSTALL_DIR}]: ${RC}"
    read -r input_dir
    [ -n "$input_dir" ] && INSTALL_DIR="$input_dir"

    printf "%b" "${GREEN}Speicherpfad STORAGE_DIR [${DEFAULT_STORAGE_DIR}]: ${RC}"
    read -r input_store
    [ -n "$input_store" ] && STORAGE_DIR="$input_store"

    INSTALL_DIR=$(realpath -m "$INSTALL_DIR")
    STORAGE_DIR=$(realpath -m "$STORAGE_DIR")
}

ensure_dirs() {
    mkdir -p "$STORAGE_DIR"
}

clone_or_update() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        printf "%b\n" "${CYAN}Repo existiert, hole Updates...${RC}"
        (cd "$INSTALL_DIR" && git pull --ff-only)
    else
        printf "%b\n" "${CYAN}Klonen von AnythingLLM...${RC}"
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
}

prepare_env_files() {
    # server env
    if [ ! -f "$INSTALL_DIR/server/.env" ]; then
        if [ -f "$INSTALL_DIR/server/.env.example" ]; then
            cp "$INSTALL_DIR/server/.env.example" "$INSTALL_DIR/server/.env"
        else
            printf "%b\n" "${RED}server/.env.example fehlt, kann .env nicht erstellen.${RC}"
            exit 1
        fi
    fi

    if grep -q '^STORAGE_DIR=' "$INSTALL_DIR/server/.env"; then
        sed -i "s#^STORAGE_DIR=.*#STORAGE_DIR=\"${STORAGE_DIR}\"#" "$INSTALL_DIR/server/.env"
    else
        printf "STORAGE_DIR=\"%s\"\n" "$STORAGE_DIR" >> "$INSTALL_DIR/server/.env"
    fi

    # frontend env
    if [ ! -f "$INSTALL_DIR/frontend/.env" ]; then
        if [ -f "$INSTALL_DIR/frontend/.env.example" ]; then
            cp "$INSTALL_DIR/frontend/.env.example" "$INSTALL_DIR/frontend/.env"
        else
            printf "VITE_API_BASE=/api\n" > "$INSTALL_DIR/frontend/.env"
        fi
    fi
    if grep -q '^VITE_API_BASE=' "$INSTALL_DIR/frontend/.env"; then
        sed -i 's#^VITE_API_BASE=.*#VITE_API_BASE=/api#' "$INSTALL_DIR/frontend/.env"
    else
        echo "VITE_API_BASE=/api" >> "$INSTALL_DIR/frontend/.env"
    fi
}

install_dependencies() {
    printf "%b\n" "${CYAN}Installiere Projekt-Abhängigkeiten (yarn setup)...${RC}"
    (cd "$INSTALL_DIR" && yarn setup)
}

build_frontend() {
    printf "%b\n" "${CYAN}Baue Frontend...${RC}"
    (cd "$INSTALL_DIR/frontend" && yarn build)
    rm -rf "$INSTALL_DIR/server/public"
    cp -R "$INSTALL_DIR/frontend/dist" "$INSTALL_DIR/server/public"
}

prepare_server() {
    printf "%b\n" "${CYAN}Prisma Migrationen & Generate...${RC}"
    (cd "$INSTALL_DIR/server" && yarn)
    (cd "$INSTALL_DIR/server" && npx prisma generate --schema=./prisma/schema.prisma)
    (cd "$INSTALL_DIR/server" && npx prisma migrate deploy --schema=./prisma/schema.prisma)
}

prepare_collector() {
    printf "%b\n" "${CYAN}Collector-Dependencies installieren...${RC}"
    (cd "$INSTALL_DIR/collector" && yarn)
}

start_services() {
    printf "%b" "${GREEN}Services jetzt starten? [y/N]: ${RC}"
    read -r start_now
    case "$start_now" in
        y|Y)
            (cd "$INSTALL_DIR/server" && NODE_ENV=production node index.js >/tmp/anythingllm-server.log 2>&1 &)
            (cd "$INSTALL_DIR/collector" && NODE_ENV=production node index.js >/tmp/anythingllm-collector.log 2>&1 &)
            printf "%b\n" "${GREEN}Server läuft auf Port 3001 (Logs: /tmp/anythingllm-*.log).${RC}"
            ;;
        *)
            printf "%b\n" "${YELLOW}Übersprungen. Manuell starten mit:${RC}"
            printf "%b\n" "  (cd ${INSTALL_DIR}/server && NODE_ENV=production node index.js)"
            printf "%b\n" "  (cd ${INSTALL_DIR}/collector && NODE_ENV=production node index.js)"
            ;;
    esac
}

main() {
    printf "%b\n" "${CYAN}AnythingLLM Bare-Metal Installation (ohne Docker)${RC}"
    assert_not_root
    checkEnv
    ensure_git
    ensure_node
    ensure_yarn
    prompt_paths
    ensure_dirs
    clone_or_update
    prepare_env_files
    install_dependencies
    build_frontend
    prepare_server
    prepare_collector
    start_services

    printf "%b\n" "${GREEN}✓ AnythingLLM wurde aus Source vorbereitet.${RC}"
    printf "%b\n" "${CYAN}Frontend-Build:${RC} ${INSTALL_DIR}/frontend/dist → server/public"
    printf "%b\n" "${CYAN}STORAGE_DIR:${RC} ${STORAGE_DIR} (in server/.env)"
    printf "%b\n" "${CYAN}Start-URL:${RC} http://localhost:3001"
}

main "$@"
