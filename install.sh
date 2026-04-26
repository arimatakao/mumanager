#!/usr/bin/env bash

set -euo pipefail

PROGRAM_NAME="mumanager"
SCRIPT_NAME="mumanager.sh"
RAW_BASE_URL="https://raw.githubusercontent.com/arimatakao/mumanager/main"
TMP_SOURCE_SCRIPT=""

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

show_help() {
  cat <<'EOF'
Install MuManager on Linux.

Usage: ./install.sh [OPTIONS]

Remote install:
  curl -fsSL https://raw.githubusercontent.com/arimatakao/mumanager/main/install.sh | bash

Options:
  --user                  Install to ~/.local/bin (default for normal users)
  --system                Install to /usr/local/bin (default for root)
  --prefix DIR            Install to DIR/bin
  --bin-dir DIR           Install directly to DIR
  --name NAME             Installed command name (default: mumanager)
  -h, --help              Show this help

Examples:
  ./install.sh
  ./install.sh --user
  sudo ./install.sh --system
  ./install.sh --bin-dir "$HOME/bin"
  curl -fsSL https://raw.githubusercontent.com/arimatakao/mumanager/main/install.sh | bash
EOF
}

script_dir() {
  local source="${BASH_SOURCE[0]}"
  while [[ -L "$source" ]]; do
    local dir
    dir=$(cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd)
    source=$(readlink "$source")
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" >/dev/null 2>&1 && pwd
}

install_file() {
  local source="$1"
  local target="$2"
  local target_dir
  target_dir=$(dirname "$target")

  mkdir -p "$target_dir"

  if command -v install >/dev/null 2>&1; then
    install -m 0755 "$source" "$target"
  else
    cp "$source" "$target"
    chmod 0755 "$target"
  fi
}

download_file() {
  local url="$1"
  local target="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$target"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$target" "$url"
  else
    die 'curl or wget is required for remote installation.'
  fi
}

cleanup() {
  [[ -n "$TMP_SOURCE_SCRIPT" ]] && rm -f "$TMP_SOURCE_SCRIPT"
  return 0
}

resolve_source_script() {
  local root_dir local_script
  root_dir=$(script_dir 2>/dev/null || pwd)
  local_script="$root_dir/$SCRIPT_NAME"

  if [[ -f "$local_script" ]]; then
    printf '%s\n' "$local_script"
    return 0
  fi

  TMP_SOURCE_SCRIPT=$(mktemp) || die 'failed to create a temporary file.'
  download_file "$RAW_BASE_URL/$SCRIPT_NAME" "$TMP_SOURCE_SCRIPT"
  printf '%s\n' "$TMP_SOURCE_SCRIPT"
}

warn_missing_dependencies() {
  local missing=()
  local dependency

  for dependency in bash find sort stat column ffprobe jq; do
    command -v "$dependency" >/dev/null 2>&1 || missing+=("$dependency")
  done

  if (( ${#missing[@]} > 0 )); then
    printf '\nWarning: missing optional/runtime dependencies:\n'
    printf '  %s\n' "${missing[@]}"
    printf '\nInstall them with your distribution package manager.\n'
    printf 'For metadata views, MuManager needs ffprobe from FFmpeg and jq.\n'
  fi

  return 0
}

mode=''
prefix=''
bin_dir=''

trap cleanup EXIT

while (( $# > 0 )); do
  case "$1" in
    --user)
      mode='user'
      shift
      ;;
    --system)
      mode='system'
      shift
      ;;
    --prefix)
      [[ $# -ge 2 ]] || die '--prefix requires a directory.'
      prefix="$2"
      shift 2
      ;;
    --bin-dir)
      [[ $# -ge 2 ]] || die '--bin-dir requires a directory.'
      bin_dir="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || die '--name requires a command name.'
      PROGRAM_NAME="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ "$PROGRAM_NAME" != */* && -n "$PROGRAM_NAME" ]] || die 'command name must not contain slashes.'

if [[ -n "$bin_dir" && -n "$prefix" ]]; then
  die 'use either --prefix or --bin-dir, not both.'
fi

if [[ -z "$bin_dir" ]]; then
  if [[ -n "$prefix" ]]; then
    bin_dir="$prefix/bin"
  elif [[ "$mode" == 'system' ]]; then
    bin_dir='/usr/local/bin'
  elif [[ "$mode" == 'user' ]]; then
    bin_dir="${HOME:?}/.local/bin"
  elif (( EUID == 0 )); then
    bin_dir='/usr/local/bin'
  else
    bin_dir="${HOME:?}/.local/bin"
  fi
fi

source_script=$(resolve_source_script)
target_script="$bin_dir/$PROGRAM_NAME"

install_file "$source_script" "$target_script"

printf 'MuManager installed successfully.\n'
printf 'Command: %s\n' "$target_script"

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *)
    printf '\nNote: %s is not in your PATH.\n' "$bin_dir"
    printf 'Add this line to your shell profile:\n'
    printf '  export PATH="%s:$PATH"\n' "$bin_dir"
    ;;
esac

warn_missing_dependencies
