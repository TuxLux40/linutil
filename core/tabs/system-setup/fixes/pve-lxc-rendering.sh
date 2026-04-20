#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Fix emoji/non-BMP rendering issues in shell startup files for Proxmox LXC web console.
# - Scans only allowed targets
# - Creates timestamped backups only when a real change is needed
# - Replaces known emoji with ASCII fallbacks
# - Removes remaining matched emoji/unicode symbols
# - Verifies no matched characters remain after patch
# - Supports --dry-run

usage() {
  echo "Usage: $0 [--dry-run]"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  echo "$*"
}

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

if [[ $# -ne 0 ]]; then
  usage >&2
  exit 2
fi

# Prefer UTF-8 handling for perl regex ranges.
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
HOME_DIR="${HOME:-/root}"

# Allowed real paths (after symlink resolution).
is_allowed_realpath() {
  local p="$1"
  case "$p" in
  /etc/profile.d/*) return 0 ;;
  /etc/bash.bashrc) return 0 ;;
  /etc/profile) return 0 ;;
  "$HOME_DIR/.bashrc") return 0 ;;
  "$HOME_DIR/.profile") return 0 ;;
  *) return 1 ;;
  esac
}

# Resolve to canonical path; fail for broken symlinks.
resolve_path() {
  local p="$1"
  realpath -e -- "$p"
}

# Skip binary files.
is_text_file() {
  local f="$1"
  grep -Iq . -- "$f"
}

# Match:
# - Any non-BMP (U+10000..U+10FFFF)
# - Emoji block-ish range U+1F000..U+1FAFF
# - Misc symbols / dingbats range U+2600..U+27BF
contains_problem_chars() {
  local f="$1"
  perl -CSDA -ne '
    if (/[\x{10000}-\x{10FFFF}\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}]/) {
      exit 0
    }
    END { exit 1 }
  ' -- "$f"
}

count_problem_chars() {
  local f="$1"
  perl -CSDA -ne '
    while (/[\x{10000}-\x{10FFFF}\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}]/g) {
      $c++
    }
    END { print(($c // 0) . "\n") }
  ' -- "$f"
}

# Apply requested replacements first, then remove any remaining matched characters.
transform_file_to_tmp() {
  local src="$1"
  local tmp="$2"
  perl -CSDA -pe '
    s/\x{1F310}/*/g;                    # 🌐 -> *
    s/\x{1F5A5}\x{FE0F}?/OS:/g;         # 🖥️ -> OS:
    s/\x{1F3E0}/HN:/g;                  # 🏠 -> HN:
    s/\x{1F4A1}/IP:/g;                  # 💡 -> IP:
    s/\x{2705}/[OK]/g;                  # ✅ -> [OK]
    s/\x{26A0}\x{FE0F}?/[!!]/g;         # ⚠️ -> [!!]
    s/\x{1F680}/-->/g;                  # 🚀 -> -->
    s/[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{10000}-\x{10FFFF}]//g;
  ' -- "$src" >"$tmp"
}

declare -A SEEN_REAL=()
declare -a CANDIDATES=()

SKIPPED_OUTSIDE=0
SKIPPED_BINARY=0
SCANNED=0
FOUND_WITH_PROBLEMS=0
CHANGED=0
BACKUPS=0

declare -a CHANGED_FILES=()
declare -a DRYRUN_FILES=()

add_candidate() {
  local input="$1"
  local real

  # File absent is not an error for optional user files.
  if [[ ! -e "$input" && ! -L "$input" ]]; then
    return 0
  fi

  if ! real="$(resolve_path "$input" 2>/dev/null)"; then
    die "Cannot resolve path (broken symlink or missing target): $input"
  fi

  if [[ ! -f "$real" ]]; then
    # Do not touch directories/devices/etc.
    return 0
  fi

  if ! is_allowed_realpath "$real"; then
    SKIPPED_OUTSIDE=$((SKIPPED_OUTSIDE + 1))
    log "Skip (outside allowed target set): $input -> $real"
    return 0
  fi

  if ! is_text_file "$real"; then
    SKIPPED_BINARY=$((SKIPPED_BINARY + 1))
    log "Skip (binary or non-text): $input -> $real"
    return 0
  fi

  if [[ -z "${SEEN_REAL[$real]+x}" ]]; then
    SEEN_REAL["$real"]=1
    CANDIDATES+=("$real")
  fi
}

# Collect from /etc/profile.d/*
if [[ -d /etc/profile.d ]]; then
  shopt -s nullglob
  for f in /etc/profile.d/*; do
    add_candidate "$f"
  done
  shopt -u nullglob
fi

# Collect explicit files
add_candidate /etc/bash.bashrc
add_candidate /etc/profile
add_candidate "$HOME_DIR/.bashrc"
add_candidate "$HOME_DIR/.profile"

if [[ "${#CANDIDATES[@]}" -eq 0 ]]; then
  log "No candidate files found."
  exit 0
fi

for file in "${CANDIDATES[@]}"; do
  SCANNED=$((SCANNED + 1))

  if ! contains_problem_chars "$file"; then
    continue
  fi

  FOUND_WITH_PROBLEMS=$((FOUND_WITH_PROBLEMS + 1))
  before_count="$(count_problem_chars "$file")"

  tmp="$(mktemp)"
  cleanup_tmp() { rm -f -- "$tmp"; }
  trap cleanup_tmp RETURN

  transform_file_to_tmp "$file" "$tmp" || die "Transformation failed for $file"

  after_tmp_count="$(count_problem_chars "$tmp")"
  if [[ "$after_tmp_count" -ne 0 ]]; then
    die "Verification failed (temporary output still contains matched characters): $file"
  fi

  # If transform results in no effective content change, do nothing.
  if cmp -s -- "$file" "$tmp"; then
    trap - RETURN
    rm -f -- "$tmp"
    continue
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: would patch $file (matched chars: $before_count -> 0)"
    DRYRUN_FILES+=("$file")
  else
    backup="${file}.bak.${TIMESTAMP}"
    if [[ -e "$backup" ]]; then
      die "Backup file already exists, refusing to overwrite: $backup"
    fi

    cp -a -- "$file" "$backup" || die "Failed to create backup: $backup"
    BACKUPS=$((BACKUPS + 1))

    # Overwrite in place while preserving existing metadata as much as possible.
    cat -- "$tmp" >"$file" || die "Failed to write patched file: $file"

    # Final verification on the written file.
    if contains_problem_chars "$file"; then
      die "Post-write verification failed: matched characters still present in $file"
    fi

    log "Patched: $file (backup: $backup, matched chars: $before_count -> 0)"
    CHANGED_FILES+=("$file")
    CHANGED=$((CHANGED + 1))
  fi

  trap - RETURN
  rm -f -- "$tmp"
done

log ""
log "Summary:"
log "  scanned files: $SCANNED"
log "  files containing matched chars: $FOUND_WITH_PROBLEMS"
log "  skipped outside allowed paths: $SKIPPED_OUTSIDE"
log "  skipped binary/non-text: $SKIPPED_BINARY"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "  dry-run files to change: ${#DRYRUN_FILES[@]}"
  if [[ "${#DRYRUN_FILES[@]}" -gt 0 ]]; then
    for f in "${DRYRUN_FILES[@]}"; do
      log "    - $f"
    done
  fi
else
  log "  changed files: $CHANGED"
  log "  backups created: $BACKUPS"
  if [[ "${#CHANGED_FILES[@]}" -gt 0 ]]; then
    for f in "${CHANGED_FILES[@]}"; do
      log "    - $f"
    done
  fi
fi

exit 0
