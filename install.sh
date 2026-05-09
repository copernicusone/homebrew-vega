#!/usr/bin/env bash
# c1-vega-plen install script for macOS.
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
readonly BIN_PATH="$INSTALL_DIR/bin/c1-vega-plen"
readonly INSTALL_JSON="$INSTALL_DIR/var/install.json"
readonly LOG_PATH="$INSTALL_DIR/var/logs/proxy.log"
readonly PLIST_LABEL="com.copernicusone.c1-vega"
readonly PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
readonly RC_BLOCK_BEGIN="# >>> c1-vega >>>"
readonly RC_BLOCK_END="# <<< c1-vega <<<"
# Source repo is private; binaries and install.sh are mirrored to the public
# Homebrew tap (`copernicusone/homebrew-vega`). Override with C1_VEGA_REPO=
# during dev to point at a private repo (only works with auth-bearing curl).
readonly REPO="${C1_VEGA_REPO:-copernicusone/homebrew-vega}"
readonly PROXY_HOST="127.0.0.1:8787"
readonly PROXY_BASE_URL="http://${PROXY_HOST}"
readonly PROXY_HEALTH_URL="${PROXY_BASE_URL}/health"
readonly LICENSE_KEY_PEPPER="c1-vega-install-v1"
readonly MIN_MACOS_MAJOR=12

REPO_ROOT_GUESS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)" || REPO_ROOT_GUESS=""
readonly REPO_ROOT_GUESS

# --- usage --------------------------------------------------------------------

usage() {
  cat <<EOF
c1-vega-plen install script for macOS.

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
        echo "error: c1-vega-plen already installed at $INSTALL_DIR" >&2
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
  local archive="c1-vega-plen-${version}-${triple}.tar.gz"
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

  # The release package wraps the binary in c1-vega-plen-<v>-<triple>/. Find it
  # robustly: look for the named binary anywhere under work.
  local found
  found="$(find "$work" -type f -name 'c1-vega-plen' -perm +111 2>/dev/null | head -1)"
  if [ -z "$found" ]; then
    # Fallback: any file named c1-vega-plen (perm bit may be lost on Linux runners
    # or when -perm +111 is unsupported by find).
    found="$(find "$work" -type f -name 'c1-vega-plen' | head -1)"
  fi
  if [ -z "$found" ]; then
    echo "error: c1-vega-plen not found in archive $archive" >&2
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
  "shell_files_patched": $shell_files,
  "launchd_label": "$PLIST_LABEL"
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
export ANTHROPIC_BASE_URL=\"http://127.0.0.1:8787\"
codex() {
  c1-vega-plen run --client codex --codex-auth chatgpt -- codex \"\$@\"
}
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

# --- launchd ------------------------------------------------------------------

render_plist() {
  mkdir -p "$(dirname "$PLIST_PATH")"
  local template="$REPO_ROOT_GUESS/scripts/install/launchd.plist.template"
  if [ -f "$template" ]; then
    sed -e "s|__BIN_PATH__|$BIN_PATH|g" \
        -e "s|__LOG_PATH__|$LOG_PATH|g" \
        "$template" > "$PLIST_PATH"
  else
    cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$PLIST_LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$BIN_PATH</string><string>start</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$LOG_PATH</string>
  <key>StandardErrorPath</key><string>$LOG_PATH</string>
  <key>EnvironmentVariables</key><dict><key>RUST_LOG</key><string>info</string></dict>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF
  fi
  chmod 644 "$PLIST_PATH"
}

load_launchd() {
  launchctl bootstrap "gui/$UID" "$PLIST_PATH"
  launchctl kickstart "gui/$UID/$PLIST_LABEL"
}

unload_launchd() {
  launchctl bootout "gui/$UID" "$PLIST_PATH" 2>/dev/null || true
}

smoke_test() {
  local i
  for i in 1 2 3 4 5; do
    if curl -sf --max-time 5 "$PROXY_HEALTH_URL" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

# --- main ---------------------------------------------------------------------

main() {
  parse_args "$@"
  preflight
  if [ "$DRY_RUN" -eq 1 ]; then
    case "$MODE" in
      install)
        echo "[DRY-RUN] would: detect arch, resolve latest release, download tarball + SHA256SUMS, verify checksum, extract to $INSTALL_DIR/bin/, run \`c1-vega-plen activate\`, write $INSTALL_JSON, patch $HOME/.zshrc, render+load $PLIST_PATH, smoke-test ${PROXY_HEALTH_URL}"
        ;;
      upgrade)
        echo "[DRY-RUN] would: download new release, replace $BIN_PATH, kickstart launchd"
        ;;
      uninstall)
        echo "[DRY-RUN] would: bootout launchd, rm $PLIST_PATH, unpatch shell rc files, rm -rf $INSTALL_DIR"
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

  archive="c1-vega-plen-${version}-${triple}.tar.gz"
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

  render_plist
  load_launchd

  if ! smoke_test; then
    unload_launchd
    rm -f "$PLIST_PATH"
    echo "error: proxy did not become healthy within 10 s" >&2
    if [ -f "$LOG_PATH" ]; then
      echo "--- last 50 log lines ---" >&2
      tail -50 "$LOG_PATH" >&2 || true
    fi
    return 1
  fi

  print_success_message "$version"
}

print_success_message() {
  local version="$1"
  cat <<EOF
✓ c1-vega-plen v$version installed and running on http://127.0.0.1:8787

Open a new terminal and run \`claude\` or \`codex\` — supported AI clients will
route through the proxy automatically.

The \`codex\` shell function uses ChatGPT auth by default. API-key mode remains
available via \`c1-vega-plen run --client codex --codex-auth api -- codex\`.

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
  "shell_files_patched": $shell_files,
  "launchd_label": "$PLIST_LABEL"
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

  archive="c1-vega-plen-${version}-${triple}.tar.gz"
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

  render_plist
  launchctl kickstart -k "gui/$UID/$PLIST_LABEL" 2>/dev/null || load_launchd

  if ! smoke_test; then
    echo "error: proxy not healthy after upgrade" >&2
    return 1
  fi

  echo "✓ Upgraded c1-vega-plen to v$version."
}

# --- uninstall flow -----------------------------------------------------------

uninstall() {
  if [ ! -f "$INSTALL_JSON" ]; then
    echo "nothing to uninstall"
    return 0
  fi

  unload_launchd
  rm -f "$PLIST_PATH"

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
✓ Removed binary, launchd unit, and shell-rc patches.

Note: Vault at ~/Library/Application Support/c1-vega/ left intact.
\`rm -rf\` it manually for a clean slate.

Backups of patched shell rc files saved as *.c1vega-uninstall-backup-<ts>.
EOF
}

if [ -z "${IS_SOURCED:-}" ]; then
  main "$@"
fi
