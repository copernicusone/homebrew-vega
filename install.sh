#!/usr/bin/env bash
# c1-vega-pl install script for macOS.
# Usage:
#   curl -fsSL <INSTALL_SCRIPT_URL> | C1_VEGA_LICENSE_KEY=<key> sh
# Modes (mutually exclusive): default install, --upgrade, --uninstall.
# Composable: --version <tag>, --dry-run.
#
# shellcheck disable=SC2034
# Constants and globals below are referenced by functions added in later
# tasks (download, install.json, launchd, etc.). Disable the unused-var
# warning file-wide so the skeleton lints clean.

set -euo pipefail

# --- constants ----------------------------------------------------------------

readonly INSTALL_DIR="$HOME/.c1-vega"
readonly BIN_PATH="$INSTALL_DIR/bin/c1-vega-pl"
readonly INSTALL_JSON="$INSTALL_DIR/var/install.json"
readonly RC_BLOCK_BEGIN="# >>> c1-vega >>>"
readonly RC_BLOCK_END="# <<< c1-vega <<<"
# Override with C1_VEGA_REPO= to point at a different repo during development.
readonly REPO="${C1_VEGA_REPO:-copernicusone/homebrew-vega}"
readonly LICENSE_KEY_PEPPER="c1-vega-install-v1"
readonly MIN_MACOS_MAJOR=12

# Legacy launchd identifiers — only referenced when tearing down old installs.
readonly PLIST_LABEL="com.copernicusone.c1-vega"
readonly PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

REPO_ROOT_GUESS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)" || REPO_ROOT_GUESS=""
readonly REPO_ROOT_GUESS

# --- usage --------------------------------------------------------------------

usage() {
  cat <<EOF
c1-vega-pl install script for macOS.

Usage:
  curl -fsSL <INSTALL_SCRIPT_URL> | C1_VEGA_LICENSE_KEY=<key> sh

Modes (mutually exclusive):
  (default)        Full install: download, activate, configure, launchd.
  --upgrade        In-place binary swap; preserve config and license.
  --uninstall      Reverse install: launchd unload, files removed, zshrc reverted.

Composable:
  --version <tag>  Pin to specific tag instead of latest.
  --dry-run        Print actions without executing.
  --help           This message.
EOF
}

# --- arg parsing --------------------------------------------------------------

MODE="install"
PIN_VERSION=""
DRY_RUN=0

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --upgrade)   MODE="upgrade"; shift ;;
      --uninstall) MODE="uninstall"; shift ;;
      --version)   PIN_VERSION="${2:-}"; shift 2 ;;
      --dry-run)   DRY_RUN=1; shift ;;
      --help|-h)   usage; exit 0 ;;
      *)           echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
}

# --- preflight ----------------------------------------------------------------

preflight() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: this script supports macOS only (detected $(uname -s))" >&2
    exit 1
  fi

  local ver major
  ver="$(sw_vers -productVersion)"
  major="${ver%%.*}"
  if [ "$major" -lt "$MIN_MACOS_MAJOR" ]; then
    echo "error: macOS $MIN_MACOS_MAJOR (Monterey) or later required (have $ver)" >&2
    exit 1
  fi

  case "$MODE" in
    install)
      if [ -z "${C1_VEGA_LICENSE_KEY:-}" ]; then
        echo "error: C1_VEGA_LICENSE_KEY env var required" >&2
        echo "       run: curl -fsSL ... | C1_VEGA_LICENSE_KEY=<key> sh" >&2
        exit 1
      fi
      if [ -f "$INSTALL_JSON" ]; then
        echo "error: c1-vega-pl already installed at $INSTALL_DIR" >&2
        echo "       use --upgrade or --uninstall" >&2
        exit 1
      fi
      ;;
    upgrade)
      if [ ! -f "$INSTALL_JSON" ]; then
        echo "error: not installed (no $INSTALL_JSON); use default mode to install" >&2
        exit 1
      fi
      ;;
    uninstall)
      if [ ! -f "$INSTALL_JSON" ]; then
        echo "nothing to uninstall (no $INSTALL_JSON)"
        exit 0
      fi
      ;;
  esac
}

# --- platform detection -------------------------------------------------------

detect_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    arm64)   echo "aarch64-apple-darwin" ;;
    x86_64)  echo "x86_64-apple-darwin" ;;
    *)       echo "unsupported arch: $m" >&2; return 1 ;;
  esac
}

# --- release resolution -------------------------------------------------------

resolve_release_tag() {
  if [ -n "${PIN_VERSION:-}" ]; then
    echo "$PIN_VERSION"
    return 0
  fi

  local api="https://api.github.com/repos/$REPO/releases/latest"
  local resp
  resp="$(curl -fsSL --max-time 30 "$api")" || return 1
  if [ -z "$resp" ]; then
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    local tag
    tag="$(echo "$resp" | jq -r '.tag_name // empty')"
    if [ -n "$tag" ] && [ "$tag" != "null" ]; then
      echo "$tag"
      return 0
    fi
  fi

  # Fallback: extract "tag_name": "v..." with grep/sed (works on bash 3.2 macOS).
  local tag
  tag="$(echo "$resp" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)"
  if [ -n "$tag" ]; then
    echo "$tag"
    return 0
  fi

  return 1
}

# --- download + verify --------------------------------------------------------

# Args: <tag> <triple> <work_dir>
download_artifacts() {
  local tag="$1" triple="$2" work="$3"
  local version="${tag#v}"
  local archive="c1-vega-pl-${version}-${triple}.tar.gz"
  local base="https://github.com/$REPO/releases/download/$tag"

  curl -fsSL --proto '=https' --tlsv1.2 --max-time 120 \
    -o "$work/$archive" "$base/$archive"
  curl -fsSL --proto '=https' --tlsv1.2 --max-time 30 \
    -o "$work/SHA256SUMS" "$base/SHA256SUMS"
}

# Args: <work_dir> <archive_filename>
verify_checksum() {
  local work="$1" archive="$2"
  ( cd "$work" && shasum -a 256 -c SHA256SUMS --ignore-missing | grep -q "$archive: OK" )
}

# --- extract ------------------------------------------------------------------

# Args: <archive_path>
extract_binary() {
  local archive="$1"
  local work
  work="$(mktemp -d -t c1vega-extract-XXXXXX)"
  tar -xzf "$archive" -C "$work"

  # The Plan D2 package.sh wraps the binary in c1-vega-pl-<v>-<triple>/. Find it
  # robustly: look for the named binary anywhere under work.
  local found
  found="$(find "$work" -type f -name 'c1-vega-pl' -perm +111 2>/dev/null | head -1)"
  if [ -z "$found" ]; then
    # Fallback: any file named c1-vega-pl (perm bit may be lost on Linux runners
    # or when -perm +111 is unsupported by find).
    found="$(find "$work" -type f -name 'c1-vega-pl' | head -1)"
  fi
  if [ -z "$found" ]; then
    echo "error: c1-vega-pl not found in archive $archive" >&2
    rm -rf "$work"
    return 1
  fi

  mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/var/logs" "$INSTALL_DIR/etc"
  cp "$found" "$BIN_PATH"
  chmod 755 "$BIN_PATH"
  rm -rf "$work"

  # Strip Gatekeeper quarantine so first run isn't blocked. Unsigned binary
  # trust model: user already accepted curl|sh trust by pasting the command.
  xattr -d com.apple.quarantine "$BIN_PATH" 2>/dev/null || true
}

# --- license-key hashing + install.json ---------------------------------------

# Hash the license key with HMAC-SHA256 keyed by a fixed pepper. We don't keep
# the raw key in install.json; only this hash, used by --upgrade to detect
# "is this the same key as before".
license_key_hash() {
  local key="$1"
  local hex
  hex="$(printf '%s' "$key" | openssl dgst -sha256 -hmac "$LICENSE_KEY_PEPPER" -hex 2>/dev/null | awk '{print $NF}')"
  if [ -z "$hex" ]; then
    hex="$(printf '%s' "$key" | openssl dgst -sha256 -hmac "$LICENSE_KEY_PEPPER" 2>/dev/null | awk '{print $NF}')"
  fi
  echo "sha256:$hex"
}

# Args: <version> <tag> <triple> <license_key> <shell_files_json> <binary_sha256>
write_install_json() {
  local version="$1" tag="$2" triple="$3" key="$4" shell_files="$5" bin_sha="$6"
  local key_hash
  key_hash="$(license_key_hash "$key")"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  mkdir -p "$INSTALL_DIR/var"
  cat > "$INSTALL_JSON" <<EOF
{
  "version": "$version",
  "tag": "$tag",
  "arch": "$triple",
  "installed_at": "$now",
  "license_key_hash": "$key_hash",
  "binary_sha256": "$bin_sha",
  "shell_files_patched": $shell_files
}
EOF
}

# Read a top-level scalar field from install.json. Args: <field>
# Uses jq if available, sed otherwise.
read_install_json() {
  local field="$1"
  if [ ! -f "$INSTALL_JSON" ]; then
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -r ".$field // empty" "$INSTALL_JSON"
    return 0
  fi
  grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$INSTALL_JSON" \
    | sed -E "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
}

# --- shell rc patch -----------------------------------------------------------

# Args: <rc_path>
# Append the c1-vega env-var block. Idempotent: if a marker pair already exists,
# replace the block in place. Backup written to <rc_path>.c1vega-backup-<ts>.
patch_shell_rc() {
  local rc="$1"

  if [ ! -f "$rc" ]; then
    case "$rc" in
      "$HOME/.zshrc") : > "$rc" ;;
      *) return 0 ;;
    esac
  fi

  local backup
  backup="$rc.c1vega-backup-$(date +%s)"
  cp "$rc" "$backup"

  local block
  block="$(cat "$REPO_ROOT_GUESS/scripts/install/zshrc-block.sh" 2>/dev/null)"
  if [ -z "$block" ]; then
    block="$RC_BLOCK_BEGIN
export PATH=\"\$HOME/.c1-vega/bin:\$PATH\"
# Wrap \`claude\` to always route through the c1-vega proxy and print the
# privacy banner. Skip when already inside a Claude Code session.
if [ -z \"\${CLAUDECODE:-}\" ] && command -v c1-vega-pl >/dev/null 2>&1; then
  claude() { command c1-vega-pl run -- claude \"\$@\"; }
fi
$RC_BLOCK_END"
  fi

  local tmp
  tmp="$(mktemp -t c1vega-rc-XXXXXX)"
  if grep -q "^$RC_BLOCK_BEGIN$" "$rc"; then
    # Pass the multi-line block via env so awk can read it without -v newline issues.
    _C1VEGA_BLOCK="$block" awk -v b="$RC_BLOCK_BEGIN" -v e="$RC_BLOCK_END" '
      $0 == b { skip = 1; print ENVIRON["_C1VEGA_BLOCK"]; next }
      skip && $0 == e { skip = 0; next }
      !skip
    ' "$rc" > "$tmp"
  else
    cp "$rc" "$tmp"
    printf '\n%s\n' "$block" >> "$tmp"
  fi
  mv "$tmp" "$rc"
}

# Args: <rc_path>
# Remove the c1-vega block (markers and content between, inclusive).
unpatch_shell_rc() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  if ! grep -q "^$RC_BLOCK_BEGIN$" "$rc"; then
    return 0
  fi

  local backup
  backup="$rc.c1vega-uninstall-backup-$(date +%s)"
  cp "$rc" "$backup"

  local tmp
  tmp="$(mktemp -t c1vega-rc-XXXXXX)"
  awk -v b="$RC_BLOCK_BEGIN" -v e="$RC_BLOCK_END" '
    $0 == b { skip = 1; next }
    skip && $0 == e { skip = 0; next }
    !skip
  ' "$rc" > "$tmp"

  # Drop a single trailing blank line (the one patch_shell_rc inserted before
  # the appended block). Use sed to remove a sequence of trailing blank lines.
  sed -i.bak -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' "$tmp" 2>/dev/null || true
  rm -f "$tmp.bak"

  mv "$tmp" "$rc"
}

# --- claude code slash commands ----------------------------------------------

# Install c1-vega-* slash commands into ~/.claude/commands/ so the user gets
# autocomplete inside Claude Code (e.g. /c1-vega-help). No-op when the dir
# does not exist (user not on Claude Code) or when source files are missing.
install_claude_commands() {
  local target="$HOME/.claude/commands"
  local source="$REPO_ROOT_GUESS/install/claude-commands"
  [ -d "$source" ] || return 0
  [ -d "$HOME/.claude" ] || return 0
  mkdir -p "$target"
  local f
  for f in "$source"/c1-vega-*.md; do
    [ -f "$f" ] || continue
    cp "$f" "$target/$(basename "$f")"
  done
}

uninstall_claude_commands() {
  local target="$HOME/.claude/commands"
  [ -d "$target" ] || return 0
  rm -f "$target"/c1-vega-*.md
}

# --- legacy launchd cleanup --------------------------------------------------

# Old installs registered a launchd plist at $PLIST_PATH and ran the proxy as
# a daemon on 127.0.0.1:8787. The wrapper-based flow makes the daemon
# redundant, so on install/upgrade/uninstall we tear it down if present.
remove_legacy_launchd() {
  if [ -f "$PLIST_PATH" ] || launchctl print "gui/$UID/$PLIST_LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$UID" "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
  fi
}

# --- main ---------------------------------------------------------------------

main() {
  parse_args "$@"
  preflight
  if [ "$DRY_RUN" -eq 1 ]; then
    case "$MODE" in
      install)
        echo "[DRY-RUN] would: detect arch, resolve latest release, download tarball + SHA256SUMS, verify checksum, extract to $INSTALL_DIR/bin/, run \`c1-vega-pl activate\`, write $INSTALL_JSON, patch $HOME/.zshrc, install Claude Code slash commands, remove any legacy launchd plist"
        ;;
      upgrade)
        echo "[DRY-RUN] would: download new release, replace $BIN_PATH, refresh slash commands, remove any legacy launchd plist"
        ;;
      uninstall)
        echo "[DRY-RUN] would: remove legacy launchd plist if present, unpatch shell rc files, remove slash commands, rm -rf $INSTALL_DIR"
        ;;
    esac
    return 0
  fi
  case "$MODE" in
    install)   install ;;
    upgrade)   upgrade ;;
    uninstall) uninstall ;;
  esac
}

# --- main install flow --------------------------------------------------------

# Run the binary's activate command. Wrapped so tests can override.
run_activate() {
  if [ "${RUN_ACTIVATE_OVERRIDE:-}" = "true" ]; then
    return 0
  fi
  if [ "${RUN_ACTIVATE_OVERRIDE:-}" = "fail" ]; then
    echo "fake activate failure" >&2
    return 1
  fi
  "$BIN_PATH" activate "$C1_VEGA_LICENSE_KEY"
}

install() {
  local triple tag version archive work bin_sha shell_files

  triple="$(detect_arch)"
  tag="$(resolve_release_tag)"
  version="${tag#v}"

  work="$(mktemp -d -t c1vega-install-XXXXXX)"
  trap 'rm -rf "$work"' EXIT

  archive="c1-vega-pl-${version}-${triple}.tar.gz"
  download_artifacts "$tag" "$triple" "$work"
  verify_checksum "$work" "$archive"

  extract_binary "$work/$archive"
  bin_sha="$(shasum -a 256 "$BIN_PATH" | awk '{print $1}')"

  if ! run_activate; then
    rm -rf "$INSTALL_DIR"
    echo "error: license activation failed" >&2
    return 1
  fi

  shell_files='[]'
  write_install_json "$version" "$tag" "$triple" "$C1_VEGA_LICENSE_KEY" "$shell_files" "$bin_sha"

  local patched=()
  local rc
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ] || [ "$rc" = "$HOME/.zshrc" ]; then
      patch_shell_rc "$rc"
      [ -f "$rc" ] && patched+=("\"$rc\"")
    fi
  done
  local patched_json="["
  if [ "${#patched[@]}" -gt 0 ]; then
    patched_json+="$(IFS=,; echo "${patched[*]}")"
  fi
  patched_json+="]"
  write_install_json "$version" "$tag" "$triple" "$C1_VEGA_LICENSE_KEY" "$patched_json" "$bin_sha"

  install_claude_commands

  # Drop any plist left over from a previous install — wrapper flow runs the
  # proxy on demand instead of via launchd.
  remove_legacy_launchd

  print_success_message "$version"
}

print_success_message() {
  local version="$1"
  cat <<EOF
✓ c1-vega-pl v$version installed.

Open a new terminal and run \`claude\` — the c1-vega proxy starts on demand,
prints a privacy banner, and routes Claude Code through it.

Inside Claude Code, /c1-vega-help lists the in-chat directives.

Tip: \`history -d \$(history 1)\` removes this command (with your license key)
from shell history.
EOF
}

# --- upgrade flow -------------------------------------------------------------

# Internal helper for upgrade(): writes install.json with a pre-computed
# license_key_hash (skip re-hashing).
write_install_json_raw() {
  local version="$1" tag="$2" triple="$3" key_hash="$4" shell_files="$5" bin_sha="$6"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$INSTALL_DIR/var"
  cat > "$INSTALL_JSON" <<EOF
{
  "version": "$version",
  "tag": "$tag",
  "arch": "$triple",
  "installed_at": "$now",
  "license_key_hash": "$key_hash",
  "binary_sha256": "$bin_sha",
  "shell_files_patched": $shell_files
}
EOF
}

upgrade() {
  if [ ! -f "$INSTALL_JSON" ]; then
    echo "error: not installed" >&2
    return 1
  fi

  local triple tag version archive work bin_sha old_hash new_hash

  triple="$(detect_arch)"
  tag="$(resolve_release_tag)"
  version="${tag#v}"

  work="$(mktemp -d -t c1vega-upgrade-XXXXXX)"
  trap 'rm -rf "$work"' EXIT

  archive="c1-vega-pl-${version}-${triple}.tar.gz"
  download_artifacts "$tag" "$triple" "$work"
  verify_checksum "$work" "$archive"
  extract_binary "$work/$archive"
  bin_sha="$(shasum -a 256 "$BIN_PATH" | awk '{print $1}')"

  if [ -n "${C1_VEGA_LICENSE_KEY:-}" ]; then
    old_hash="$(read_install_json license_key_hash)"
    new_hash="$(license_key_hash "$C1_VEGA_LICENSE_KEY")"
    if [ "$old_hash" != "$new_hash" ]; then
      if ! run_activate; then
        echo "error: re-activation failed" >&2
        return 1
      fi
    fi
  fi

  local patched_json
  if command -v jq >/dev/null 2>&1; then
    patched_json="$(jq -c '.shell_files_patched' "$INSTALL_JSON")"
  else
    patched_json='[]'
  fi
  local key_for_hash="${C1_VEGA_LICENSE_KEY:-__keep_old__}"
  if [ "$key_for_hash" = "__keep_old__" ]; then
    local existing_hash
    existing_hash="$(read_install_json license_key_hash)"
    write_install_json_raw "$version" "$tag" "$triple" "$existing_hash" "$patched_json" "$bin_sha"
  else
    write_install_json "$version" "$tag" "$triple" "$C1_VEGA_LICENSE_KEY" "$patched_json" "$bin_sha"
  fi

  install_claude_commands
  remove_legacy_launchd

  echo "✓ Upgraded c1-vega-pl to v$version."
}

# --- uninstall flow -----------------------------------------------------------

uninstall() {
  if [ ! -f "$INSTALL_JSON" ]; then
    echo "nothing to uninstall"
    return 0
  fi

  remove_legacy_launchd

  uninstall_claude_commands

  local shell_files
  if command -v jq >/dev/null 2>&1; then
    shell_files="$(jq -r '.shell_files_patched[]' "$INSTALL_JSON" 2>/dev/null)"
  else
    shell_files="$(grep -A 1 '"shell_files_patched"' "$INSTALL_JSON" | grep -o '"[^"]*"' | tail -n +2 | sed 's/"//g')"
  fi
  if [ -n "$shell_files" ]; then
    local rc
    while IFS= read -r rc; do
      [ -n "$rc" ] && unpatch_shell_rc "$rc"
    done <<< "$shell_files"
  fi

  rm -rf "$INSTALL_DIR"

  cat <<EOF
✓ Removed binary, shell-rc patches, Claude Code slash commands, and any
  legacy launchd plist.

Note: Vault at ~/Library/Application Support/c1-vega/ left intact.
\`rm -rf\` it manually for a clean slate.

Backups of patched shell rc files saved as *.c1vega-uninstall-backup-<ts>.
EOF
}

if [ -z "${IS_SOURCED:-}" ]; then
  main "$@"
fi
