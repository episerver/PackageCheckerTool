#!/usr/bin/env bash
# Optimizely DXP NuGet Version Checker
# Purpose-built for Azure App Service Linux / Kudu SSH.
#
# Usage:
#   bash nugetchk.sh [--debug] [--deps FILE] [APP_ROOT | DEPS_FILE]

set -Eeuo pipefail

TOOL_NAME="Optimizely DXP NuGet Version Checker"
TOOL_VERSION="1.1.0"
DEFAULT_APP_ROOT="/app"
NUGET_REGISTRATION_BASE="https://nuget.optimizely.com/v3/registration"
JQ_VERSION="1.8.2"

DEBUG=false
APP_ROOT="$DEFAULT_APP_ROOT"
DEPS_OVERRIDE=""
TEMP_ROOT=""

usage() {
  cat <<'EOF'
Usage: bash nugetchk.sh [options] [app_root | deps_file]

Options:
  -f, --deps FILE   Use a specific .deps.json file
  -d, --debug       Print diagnostic messages to stderr
  -h, --help        Show this help

The default application root is /app. A positional argument ending in
.deps.json is treated as --deps; another positional argument is used as the
application root.
EOF
}

log() { printf '[nugetchk] %s\n' "$*" >&2; }
debug() { [[ "$DEBUG" == true ]] && printf '[nugetchk] DEBUG: %s\n' "$*" >&2 || true; }
warn() { printf '[nugetchk] WARNING: %s\n' "$*" >&2; }
fatal() { printf '[nugetchk] ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--debug) DEBUG=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -f|--deps)
      [[ $# -ge 2 ]] || fatal "$1 requires a file path"
      DEPS_OVERRIDE="$2"; shift 2 ;;
    --deps=*)
      DEPS_OVERRIDE="${1#*=}"
      [[ -n "$DEPS_OVERRIDE" ]] || fatal "--deps requires a file path"
      shift ;;
    *.deps.json) DEPS_OVERRIDE="$1"; shift ;;
    -*) fatal "Unknown option: $1" ;;
    *) APP_ROOT="$1"; shift ;;
  esac
done

command_exists() { command -v "$1" >/dev/null 2>&1; }
require_command() { command_exists "$1" || fatal "Required command not found: $1"; }

setup_workspace() {
  TEMP_ROOT=$(mktemp -d)
  trap '[[ -n "${TEMP_ROOT:-}" ]] && rm -rf "$TEMP_ROOT"' EXIT
}

sha256_of() {
  local file="$1"
  if command_exists sha256sum; then
    sha256sum "$file" | awk '{print $1}'
  elif command_exists shasum; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    fatal "A SHA-256 utility is required"
  fi
}

secure_download() {
  local url="$1" destination="$2"
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 45 \
    -fsSL -A "nugetchk/${TOOL_VERSION}" -o "$destination" "$url"
}

install_jq_if_needed() {
  command_exists jq && return 0

  local machine url checksum binary actual
  machine=$(uname -m)
  case "$machine" in
    x86_64|amd64)
      url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64"
      checksum="b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f" ;;
    aarch64|arm64)
      url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-arm64"
      checksum="8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309" ;;
    *) fatal "Automatic jq installation does not support architecture: $machine" ;;
  esac

  if [[ -n "${NUGETCHK_JQ_URL:-}" || -n "${NUGETCHK_JQ_SHA256:-}" ]]; then
    [[ -n "${NUGETCHK_JQ_URL:-}" && -n "${NUGETCHK_JQ_SHA256:-}" ]] || \
      fatal "NUGETCHK_JQ_URL and NUGETCHK_JQ_SHA256 must be set together"
    url="$NUGETCHK_JQ_URL"
    checksum="$NUGETCHK_JQ_SHA256"
  fi

  binary="$TEMP_ROOT/jq"
  log "Using temporary, checksum-verified JSON helper (jq ${JQ_VERSION})"
  secure_download "$url" "$binary" || fatal "Unable to download jq"
  actual=$(sha256_of "$binary")
  [[ "$actual" == "$checksum" ]] || fatal "Downloaded jq checksum does not match"
  chmod 0700 "$binary"
  export PATH="$TEMP_ROOT:$PATH"
  command_exists jq || fatal "Temporary jq binary cannot be executed"
}

source_location() {
  local source_path="${BASH_SOURCE[0]:-}"
  if [[ -n "$source_path" && -f "$source_path" ]]; then
    cd "$(dirname "$source_path")" && pwd
  else
    pwd
  fi
}

locate_deps_file() {
  if [[ -n "$DEPS_OVERRIDE" ]]; then
    [[ -f "$DEPS_OVERRIDE" ]] || fatal "Dependency file not found: $DEPS_OVERRIDE"
    printf '%s\n' "$DEPS_OVERRIDE"
    return
  fi

  local location candidate
  local locations=("." "$(source_location)" "$APP_ROOT" "/app" "/home/site/wwwroot")
  for location in "${locations[@]}"; do
    [[ -d "$location" ]] || continue
    debug "Searching for .deps.json under $location"
    candidate=$(find "$location" -maxdepth 3 -type f -name '*.deps.json' -print 2>/dev/null | sort | head -n 1)
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  fatal "No .deps.json file was found"
}

read_installed_packages() {
  local deps_file="$1" output_file="$2"
  jq '[
    (.libraries // {} | to_entries[]) |
    (.key | split("/")) as $parts |
    select(($parts | length) >= 2) |
    select($parts[0] | test("^(EPiServer|Optimizely)[A-Za-z0-9._-]*$")) |
    select($parts[1] | test("^[0-9]+([.][0-9A-Za-z-]+)*([+][0-9A-Za-z.-]+)?$")) |
    {name: $parts[0], version: $parts[1]}
  ] | unique_by(.name) | sort_by(.name)' "$deps_file" > "$output_file" || \
    fatal "Unable to parse dependency file: $deps_file"
}

version_parts() {
  local version="${1%%+*}" core
  core="${version%%-*}"
  local major=0 minor=0 patch=0
  IFS=. read -r major minor patch _ <<< "$core"
  [[ "$major" =~ ^[0-9]+$ ]] || major=0
  [[ "$minor" =~ ^[0-9]+$ ]] || minor=0
  [[ "$patch" =~ ^[0-9]+$ ]] || patch=0
  printf '%d %d %d\n' "$major" "$minor" "$patch"
}

version_is_newer() {
  local candidate_major candidate_minor candidate_patch current_major current_minor current_patch
  read -r candidate_major candidate_minor candidate_patch <<< "$(version_parts "$1")"
  read -r current_major current_minor current_patch <<< "$(version_parts "$2")"
  ((candidate_major > current_major)) && return 0
  ((candidate_major < current_major)) && return 1
  ((candidate_minor > current_minor)) && return 0
  ((candidate_minor < current_minor)) && return 1
  ((candidate_patch > current_patch))
}

format_version_gap() {
  local installed="$1" latest="$2"
  [[ -z "$latest" || "$latest" == unknown ]] && { printf '?\n'; return; }
  [[ "$installed" == "$latest" ]] && { printf 'up to date\n'; return; }
  if version_is_newer "$installed" "$latest"; then
    printf 'ahead\n'
    return
  fi

  local installed_major installed_minor installed_patch latest_major latest_minor latest_patch
  read -r installed_major installed_minor installed_patch <<< "$(version_parts "$installed")"
  read -r latest_major latest_minor latest_patch <<< "$(version_parts "$latest")"

  local components=() joined index
  ((latest_major > installed_major)) && components+=("$((latest_major-installed_major))maj")
  ((latest_minor > installed_minor)) && components+=("$((latest_minor-installed_minor))min")
  ((latest_patch > installed_patch)) && components+=("$((latest_patch-installed_patch))pat")

  if [[ ${#components[@]} -eq 0 ]]; then
    printf 'up to date\n'
    return
  fi

  joined="${components[0]}"
  for ((index=1; index<${#components[@]}; index++)); do
    joined+=", ${components[$index]}"
  done
  printf '+%s\n' "$joined"
}

https_get() {
  local url="$1"
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 30 \
    -fsSL -A "nugetchk/${TOOL_VERSION}" "$url"
}

collect_package_versions() {
  local package_name="$1" destination="$2" package_id root_json page_url page_json
  package_id=$(printf '%s' "$package_name" | tr '[:upper:]' '[:lower:]')
  root_json=$(https_get "$NUGET_REGISTRATION_BASE/$package_id/index.json") || return 1

  : > "$destination"
  jq -r '.items[]?.items[]?.catalogEntry | select(.listed == true) | .version // empty | select(contains("-") | not)' <<< "$root_json" >> "$destination"

  while IFS= read -r page_url; do
    [[ -n "$page_url" ]] || continue
    if [[ "$page_url" != https://nuget.optimizely.com/* ]]; then
      warn "Ignoring unexpected NuGet registration URL for $package_name"
      continue
    fi
    page_json=$(https_get "$page_url") || continue
    jq -r '.items[]?.catalogEntry | select(.listed == true) | .version // empty | select(contains("-") | not)' <<< "$page_json" >> "$destination"
  done < <(jq -r '.items[]? | select((.items // null) == null) | ."@id" // empty' <<< "$root_json")

  sort -Vu "$destination" -o "$destination"
  [[ -s "$destination" ]]
}

lookup_latest_version() {
  local package_name="$1" versions_file="$TEMP_ROOT/versions.$RANDOM" latest
  if ! collect_package_versions "$package_name" "$versions_file"; then
    rm -f "$versions_file"
    printf 'unknown\n'
    return
  fi
  latest=$(tail -n 1 "$versions_file")
  rm -f "$versions_file"
  printf '%s\n' "${latest:-unknown}"
}

main() {
  local required
  for required in curl find sort awk tr head tail; do
    require_command "$required"
  done
  setup_workspace
  install_jq_if_needed

  echo ""
  echo "======================================================================"
  echo "  $TOOL_NAME v$TOOL_VERSION"
  echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "======================================================================"

  local deps_file installed package_count results_file
  deps_file=$(locate_deps_file)
  installed="$TEMP_ROOT/installed.json"
  results_file="$TEMP_ROOT/results.tsv"

  log "Using dependency file: $deps_file"
  read_installed_packages "$deps_file" "$installed"
  package_count=$(jq 'length' "$installed")
  if [[ "$package_count" -eq 0 ]]; then
    echo ""
    echo "  No EPiServer/Optimizely packages found. Nothing to check."
    return
  fi

  echo ""
  echo "  Found $package_count EPiServer/Optimizely packages in $(basename "$deps_file")"
  echo ""
  echo "  Querying nuget.optimizely.com for latest stable versions ..."

  local row package installed_version latest delta
  local updates=0 current=0 failures=0
  : > "$results_file"
  while IFS= read -r row; do
    package=$(jq -r '.name' <<< "$row")
    installed_version=$(jq -r '.version' <<< "$row")
    latest=$(lookup_latest_version "$package")
    delta=$(format_version_gap "$installed_version" "$latest")
    printf '%s\t%s\t%s\t%s\n' "$package" "$installed_version" "$latest" "$delta" >> "$results_file"

    if [[ "$latest" == unknown ]]; then
      failures=$((failures + 1))
    elif [[ "$delta" == "up to date" || "$delta" == ahead ]]; then
      current=$((current + 1))
    else
      updates=$((updates + 1))
    fi
  done < <(jq -c '.[]' "$installed")

  echo ""
  printf '  %-40s %-14s %-14s %s\n' "PACKAGE" "INSTALLED" "LATEST" "DELTA"
  printf '  %-40s %-14s %-14s %s\n' "-------" "---------" "------" "-----"
  while IFS=$'\t' read -r package installed_version latest delta; do
    printf '  %-40s %-14s %-14s %s\n' "$package" "$installed_version" "$latest" "$delta"
  done < "$results_file"

  echo ""
  echo "  ----------------------------------------------------------------------"
  echo "  Total packages scanned:       $package_count"
  echo "  Updates available:            $updates"
  echo "  Up to date or ahead:          $current"
  echo "  Version lookup failures:      $failures"
  echo ""
  echo "  No files saved. Temporary working data will be removed automatically."
  echo "======================================================================"
}

[[ "${__TESTING:-}" == 1 ]] || main
