#!/usr/bin/env bash
# Legacy/internal c1-vega-en install script for macOS and Linux.
# Public macOS/Linux installs should use Homebrew:
#   brew tap copernicusone/vega && brew install c1-vega-en
# Usage:
#   curl -fsSL <INSTALL_SCRIPT_URL> | C1_VEGA_LICENSE_KEY=<key> bash
# Modes (mutually exclusive): default install, --upgrade, --uninstall.
# Composable: --version <tag>, --dry-run.
#
# shellcheck disable=SC2034
# Constants and globals below are referenced by functions added in later
# tasks (download, install.json, shell integration, etc.). Disable the
# unused-var warning file-wide so the skeleton lints clean.

set -euo pipefail

# --- constants ----------------------------------------------------------------

readonly INSTALL_DIR="$HOME/.c1-vega"
readonly SKU_ID="c1-vega-en"
readonly BINARY_NAME="c1-vega-en"
readonly INSTALL_SCRIPT_NAME="install-en.sh"
readonly BIN_PATH="$INSTALL_DIR/bin/$BINARY_NAME"
readonly INSTALL_JSON="$INSTALL_DIR/var/install.json"
readonly RC_BLOCK_BEGIN="# >>> c1-vega >>>"
readonly RC_BLOCK_END="# <<< c1-vega <<<"
# Source repo is private; binaries and per-sku installers are mirrored to the public
# Homebrew tap (`copernicusone/homebrew-vega`). Override with C1_VEGA_REPO=
# during dev to point at a private repo (only works with auth-bearing curl).
readonly REPO="${C1_VEGA_REPO:-copernicusone/homebrew-vega}"
readonly LICENSE_KEY_PEPPER="c1-vega-install-v1"
readonly MIN_MACOS_MAJOR=12

REPO_ROOT_GUESS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)" || REPO_ROOT_GUESS=""
readonly REPO_ROOT_GUESS

# --- usage --------------------------------------------------------------------

usage() {
  cat <<EOF
Legacy/internal $BINARY_NAME install script for macOS and Linux.

Public macOS/Linux installs should use Homebrew:
  brew tap copernicusone/vega && brew install c1-vega-en

Usage:
  curl -fsSL https://raw.githubusercontent.com/copernicusone/homebrew-vega/main/$INSTALL_SCRIPT_NAME | C1_VEGA_LICENSE_KEY=<key> bash

Modes (mutually exclusive):
  (default)        Full install: download, activate, configure shell wrappers.
  --upgrade        In-place binary swap; preserve config and license.
  --uninstall      Reverse install: shell rc reverted, files removed.

Composable:
  --version $SKU_ID-v0.1.0  Pin to a specific $SKU_ID release tag.
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
  local os
  os="$(uname -s)"
  case "$os" in
    Darwin)
      local ver major
      ver="$(sw_vers -productVersion)"
      major="${ver%%.*}"
      if [ "$major" -lt "$MIN_MACOS_MAJOR" ]; then
        echo "error: macOS $MIN_MACOS_MAJOR (Monterey) or later required (have $ver)" >&2
        exit 1
      fi
      ;;
    Linux)
      ;;
    *)
      echo "error: unsupported OS: $os" >&2
      exit 1
      ;;
  esac

  case "$MODE" in
    install)
      if [ -f "$INSTALL_JSON" ]; then
        ensure_existing_sku_matches || exit 1
        echo "error: $BINARY_NAME already installed at $INSTALL_DIR" >&2
        echo "       use --upgrade or --uninstall" >&2
        exit 1
      fi
      if [ -z "${C1_VEGA_LICENSE_KEY:-}" ]; then
        echo "error: C1_VEGA_LICENSE_KEY env var required" >&2
        echo "       run: curl -fsSL ... | C1_VEGA_LICENSE_KEY=<key> bash" >&2
        exit 1
      fi
      ;;
    upgrade)
      if [ ! -f "$INSTALL_JSON" ]; then
        echo "error: not installed (no $INSTALL_JSON); use default mode to install" >&2
        exit 1
      fi
      ensure_existing_sku_matches || exit 1
      ;;
    uninstall)
      if [ ! -f "$INSTALL_JSON" ]; then
        echo "nothing to uninstall (no $INSTALL_JSON)"
        exit 0
      fi
      ensure_existing_sku_matches || exit 1
      ;;
  esac
}

# --- platform detection -------------------------------------------------------

detect_arch() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os:$arch" in
    Darwin:arm64)  echo "aarch64-apple-darwin" ;;
    Darwin:x86_64) echo "x86_64-apple-darwin" ;;
    Linux:x86_64)  echo "x86_64-unknown-linux-gnu" ;;
    Linux:aarch64) echo "aarch64-unknown-linux-gnu" ;;
    Linux:arm64)   echo "aarch64-unknown-linux-gnu" ;;
    Darwin:*)      echo "unsupported arch for macOS: $arch" >&2; return 1 ;;
    Linux:*)       echo "unsupported arch for Linux: $arch" >&2; return 1 ;;
    *)             echo "unsupported OS: $os" >&2; return 1 ;;
  esac
}

# --- release resolution -------------------------------------------------------

version_from_tag() {
  local tag="$1"
  echo "${tag#"$SKU_ID"-v}"
}

is_stable_tag() {
  local tag="$1" version
  case "$tag" in
    "$SKU_ID"-v*) ;;
    *) return 1 ;;
  esac
  version="$(version_from_tag "$tag")"
  case "$version" in
    *-*) return 1 ;;
  esac
  echo "$version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+$'
}

sort_semver_tags() {
  while IFS= read -r tag; do
    [ -n "$tag" ] || continue
    is_stable_tag "$tag" || continue
    local version major minor patch
    version="$(version_from_tag "$tag")"
    major="${version%%.*}"
    version="${version#*.}"
    minor="${version%%.*}"
    patch="${version#*.}"
    printf '%010d.%010d.%010d %s\n' "$major" "$minor" "$patch" "$tag"
  done | sort | awk '{print $2}'
}

resolve_release_tag() {
  if [ -n "${PIN_VERSION:-}" ]; then
    if ! is_stable_tag "$PIN_VERSION"; then
      echo "error: pinned release $PIN_VERSION does not match $SKU_ID stable release tags" >&2
      return 1
    fi
    echo "$PIN_VERSION"
    return 0
  fi

  local api="https://api.github.com/repos/$REPO/releases?per_page=100"
  local resp tags tag
  resp="$(curl -fsSL --max-time 30 "$api")" || return 1
  if [ -z "$resp" ]; then
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    tags="$(echo "$resp" | jq -r --arg prefix "$SKU_ID-v" '.[] | select((.tag_name | startswith($prefix)) and (.prerelease | not)) | .tag_name' 2>/dev/null || true)"
    tag="$(echo "$tags" | sort_semver_tags | tail -1)"
    if [ -n "$tag" ]; then
      echo "$tag"
      return 0
    fi
  fi

  tags="$(echo "$resp" | tr '\n' ' ' | sed 's/},[[:space:]]*{/}\
{/g' | grep '"prerelease"[[:space:]]*:[[:space:]]*false' | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"'"$SKU_ID"'-v[0-9][0-9.]*"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  tag="$(echo "$tags" | sort_semver_tags | tail -1)"
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
  local version
  version="$(version_from_tag "$tag")"
  local archive="${BINARY_NAME}-${version}-${triple}.tar.gz"
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

  # The release package wraps the binary in $BINARY_NAME-<v>-<triple>/. Find it
  # robustly: look for the named binary anywhere under work.
  local found
  found="$(find "$work" -type f -name "$BINARY_NAME" -perm +111 2>/dev/null | head -1)"
  if [ -z "$found" ]; then
    # Fallback: any file named $BINARY_NAME (perm bit may be lost on Linux runners
    # or when -perm +111 is unsupported by find).
    found="$(find "$work" -type f -name "$BINARY_NAME" | head -1)"
  fi
  if [ -z "$found" ]; then
    echo "error: $BINARY_NAME not found in archive $archive" >&2
    rm -rf "$work"
    return 1
  fi

  mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/var"
  cp "$found" "$BIN_PATH"
  chmod 755 "$BIN_PATH"
  rm -rf "$work"

  # Strip Gatekeeper quarantine so first run isn't blocked. Unsigned binary
  # trust model: user already accepted remote installer execution or curl piped to bash.
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
  "sku": "$SKU_ID",
  "binary": "$BINARY_NAME",
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

infer_existing_sku() {
  local existing binary tag
  existing="$(read_install_json sku || true)"
  if [ -n "$existing" ]; then
    echo "$existing"
    return 0
  fi

  binary="$(read_install_json binary || true)"
  case "$binary" in
    c1-vega-plen|c1-vega-en)
      echo "$binary"
      return 0
      ;;
  esac

  tag="$(read_install_json tag || true)"
  case "$tag" in
    c1-vega-plen-v*)
      echo "c1-vega-plen"
      return 0
      ;;
    c1-vega-en-v*)
      echo "c1-vega-en"
      return 0
      ;;
  esac

  echo "c1-vega-plen"
}

ensure_existing_sku_matches() {
  if [ ! -f "$INSTALL_JSON" ]; then
    return 0
  fi
  local existing
  existing="$(infer_existing_sku)"
  if [ "$existing" != "$SKU_ID" ]; then
    echo "error: installed sku $existing does not match $SKU_ID" >&2
    return 1
  fi
}

# --- shell rc patch -----------------------------------------------------------

# Args: <rc_path>
# Append the c1-vega shell-wrapper block. Idempotent: if a marker pair already
# exists, replace the block in place. Backup written to <rc_path>.c1vega-backup-<ts>.
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
  block="$RC_BLOCK_BEGIN
export PATH=\"\$HOME/.c1-vega/bin:\$PATH\"
_c1_vega_claude() {
  $BINARY_NAME run --client anthropic -- claude \"\$@\"
}

claude() {
  _c1_vega_claude \"\$@\"
}

_c1_vega_codex() {
  $BINARY_NAME run --client codex --codex-auth chatgpt -- codex \"\$@\"
}

codex() {
  _c1_vega_codex \"\$@\"
}
$RC_BLOCK_END"

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

# --- main ---------------------------------------------------------------------

main() {
  parse_args "$@"
  preflight
  if [ "$DRY_RUN" -eq 1 ]; then
    case "$MODE" in
      install)
        echo "[DRY-RUN] would: detect arch, resolve latest $SKU_ID release, download tarball + SHA256SUMS, verify checksum, extract to $INSTALL_DIR/bin/, run \`$BINARY_NAME activate\`, write $INSTALL_JSON, patch $HOME/.zshrc, install shell wrappers"
        ;;
      upgrade)
        echo "[DRY-RUN] would: download new release, replace $BIN_PATH, refresh install metadata"
        ;;
      uninstall)
        echo "[DRY-RUN] would: unpatch shell rc files, rm -rf $INSTALL_DIR"
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

  if [ -f "$INSTALL_JSON" ]; then
    ensure_existing_sku_matches || return 1
    echo "error: $BINARY_NAME already installed at $INSTALL_DIR" >&2
    echo "       use --upgrade or --uninstall" >&2
    return 1
  fi

  triple="$(detect_arch)"
  tag="$(resolve_release_tag)"
  version="$(version_from_tag "$tag")"

  work="$(mktemp -d -t c1vega-install-XXXXXX)"
  trap 'rm -rf "${work:-}"' EXIT

  archive="${BINARY_NAME}-${version}-${triple}.tar.gz"
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

  print_success_message "$version"
}

print_success_message() {
  local version="$1"
  cat <<EOF
✓ $BINARY_NAME v$version installed.

Open a new terminal and run \`claude\` or \`codex\` — the shell wrappers start
the proxy on demand.

The \`codex\` wrapper uses ChatGPT auth by default. If you alias \`claude\` or
\`codex\` to an absolute path, point the alias at \`_c1_vega_claude\` or
\`_c1_vega_codex\` instead, or call \`$BINARY_NAME run\` directly.

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
  "sku": "$SKU_ID",
  "binary": "$BINARY_NAME",
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
  ensure_existing_sku_matches || return 1

  local triple tag version archive work bin_sha old_hash new_hash

  triple="$(detect_arch)"
  tag="$(resolve_release_tag)"
  version="$(version_from_tag "$tag")"

  work="$(mktemp -d -t c1vega-upgrade-XXXXXX)"
  trap 'rm -rf "${work:-}"' EXIT

  archive="${BINARY_NAME}-${version}-${triple}.tar.gz"
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

  echo "✓ Upgraded $BINARY_NAME to v$version."
}

# --- uninstall flow -----------------------------------------------------------

uninstall() {
  if [ ! -f "$INSTALL_JSON" ]; then
    echo "nothing to uninstall"
    return 0
  fi
  ensure_existing_sku_matches || return 1

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
✓ Removed binary and shell-rc patches.

Note: Vault at ~/Library/Application Support/c1-vega/ left intact.
\`rm -rf\` it manually for a clean slate.

Backups of patched shell rc files saved as *.c1vega-uninstall-backup-<ts>.
EOF
}

if [ -z "${IS_SOURCED:-}" ]; then
  main "$@"
fi
