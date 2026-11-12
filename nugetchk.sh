#!/usr/bin/env bash
# Optimizely DXP NuGet Health Checker
# Purpose-built for Azure App Service Linux / Kudu SSH.
#
# Usage:
#   bash nugetchk.sh [--notes] [--debug] [--refresh] [--deps FILE]
#                    [--output-dir DIR] [APP_ROOT | DEPS_FILE]

set -Eeuo pipefail

TOOL_NAME="Optimizely DXP NuGet Health Checker"
TOOL_VERSION="1.0.0"
DEFAULT_APP_ROOT="/home/site/wwwroot"
NUGET_REGISTRATION_BASE="https://nuget.optimizely.com/v3/registration"
RELEASE_NOTES_BASE="https://world.optimizely.com/documentation/Release-Notes/"
JQ_VERSION="1.8.2"

SHOW_NOTES=false
DEBUG=false
FORCE_REFRESH=false
APP_ROOT="$DEFAULT_APP_ROOT"
DEPS_OVERRIDE=""
OUTPUT_OVERRIDE=""
TEMP_ROOT=""

ISSUE_TERMS=(
  "memory leak"
  "out of memory"
  "high memory"
  "performance"
  "slow"
  "timeout"
  "deadlock"
  "thread"
  "cpu"
)

usage() {
  cat <<'EOF'
Usage: bash nugetchk.sh [options] [app_root | deps_file]

Options:
  -n, --notes             Show release notes between installed and latest
  -f, --deps FILE         Use a specific .deps.json file
  -o, --output-dir DIR    Directory for reports and the release-note cache
      --refresh           Ignore an existing release-note cache
  -d, --debug             Print diagnostic messages to stderr
  -h, --help              Show this help

The default application root is /home/site/wwwroot. A positional argument
ending in .deps.json is treated as --deps; another positional argument is
used as the application root.
EOF
}

log() { printf '[nugetchk] %s\n' "$*" >&2; }
debug() { [[ "$DEBUG" == true ]] && printf '[nugetchk] DEBUG: %s\n' "$*" >&2 || true; }
warn() { printf '[nugetchk] WARNING: %s\n' "$*" >&2; }
fatal() { printf '[nugetchk] ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--notes) SHOW_NOTES=true; shift ;;
    -d|--debug) DEBUG=true; shift ;;
    --refresh) FORCE_REFRESH=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -f|--deps)
      [[ $# -ge 2 ]] || fatal "$1 requires a file path"
      DEPS_OVERRIDE="$2"; shift 2 ;;
    --deps=*)
      DEPS_OVERRIDE="${1#*=}"
      [[ -n "$DEPS_OVERRIDE" ]] || fatal "--deps requires a file path"
      shift ;;
    -o|--output-dir)
      [[ $# -ge 2 ]] || fatal "$1 requires a directory"
      OUTPUT_OVERRIDE="$2"; shift 2 ;;
    --output-dir=*)
      OUTPUT_OVERRIDE="${1#*=}"
      [[ -n "$OUTPUT_OVERRIDE" ]] || fatal "--output-dir requires a directory"
      shift ;;
    *.deps.json) DEPS_OVERRIDE="$1"; shift ;;
    -*) fatal "Unknown option: $1" ;;
    *) APP_ROOT="$1"; shift ;;
  esac
done

command_exists() { command -v "$1" >/dev/null 2>&1; }
require_command() { command_exists "$1" || fatal "Required command not found: $1"; }

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

  local machine url checksum cache_dir binary temp actual
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

  cache_dir="${NUGETCHK_CACHE_DIR:-${HOME:-/tmp}/.cache/nugetchk}"
  mkdir -p "$cache_dir" || fatal "Cannot create cache directory: $cache_dir"
  binary="$cache_dir/jq-${JQ_VERSION}-${machine}"

  if [[ -f "$binary" ]]; then
    actual=$(sha256_of "$binary")
    [[ "$actual" == "$checksum" ]] || fatal "Cached jq checksum does not match"
  else
    log "jq was not found; downloading and verifying jq ${JQ_VERSION}"
    temp=$(mktemp "$cache_dir/.jq.XXXXXX")
    if ! secure_download "$url" "$temp"; then
      rm -f "$temp"
      fatal "Unable to download jq"
    fi
    actual=$(sha256_of "$temp")
    if [[ "$actual" != "$checksum" ]]; then
      rm -f "$temp"
      fatal "Downloaded jq checksum does not match"
    fi
    chmod 0755 "$temp"
    mv "$temp" "$binary"
  fi

  ln -sfn "$binary" "$cache_dir/jq"
  export PATH="$cache_dir:$PATH"
  command_exists jq || fatal "jq was installed but cannot be executed"
}

setup_workspace() {
  TEMP_ROOT=$(mktemp -d)
  trap '[[ -n "${TEMP_ROOT:-}" ]] && rm -rf "$TEMP_ROOT"' EXIT
}

source_location() {
  local source_path="${BASH_SOURCE[0]:-}"
  if [[ -n "$source_path" && -f "$source_path" ]]; then
    cd "$(dirname "$source_path")" && pwd
  else
    pwd
  fi
}

resolve_output_dir() {
  local fallback
  fallback=$(source_location)
  OUTPUT_DIR="${OUTPUT_OVERRIDE:-${NUGETCHK_OUTPUT_DIR:-$fallback}}"
  mkdir -p "$OUTPUT_DIR" || fatal "Cannot create output directory: $OUTPUT_DIR"
  [[ -w "$OUTPUT_DIR" ]] || fatal "Output directory is not writable: $OUTPUT_DIR"
  OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
  REPORT_PATH="$OUTPUT_DIR/nugetchk_report.json"
  ISSUES_PATH="$OUTPUT_DIR/known_issues.json"
}

locate_deps_file() {
  if [[ -n "$DEPS_OVERRIDE" ]]; then
    [[ -f "$DEPS_OVERRIDE" ]] || fatal "Dependency file not found: $DEPS_OVERRIDE"
    printf '%s\n' "$DEPS_OVERRIDE"
    return
  fi

  local location candidate
  local locations=("." "$(source_location)" "$APP_ROOT")
  for location in "${locations[@]}"; do
    [[ -d "$location" ]] || continue
    debug "Searching for .deps.json under $location"
    candidate=$(find "$location" -maxdepth 2 -type f -name '*.deps.json' -print 2>/dev/null | sort | head -n 1)
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

version_at_least() {
  [[ "$1" == "$2" ]] || version_is_newer "$1" "$2"
}

format_version_gap() {
  local installed="$1" latest="$2"
  [[ -z "$latest" || "$latest" == unknown ]] && { printf '?\n'; return; }
  [[ "$installed" == "$latest" ]] && { printf 'up to date\n'; return; }

  local imaj imin ipat lmaj lmin lpat
  read -r imaj imin ipat <<< "$(version_parts "$installed")"
  read -r lmaj lmin lpat <<< "$(version_parts "$latest")"
  local components=()
  ((lmaj > imaj)) && components+=("$((lmaj-imaj))maj")
  ((lmin > imin)) && components+=("$((lmin-imin))min")
  ((lpat > ipat)) && components+=("$((lpat-ipat))pat")
  if [[ ${#components[@]} -eq 0 ]]; then
    printf 'up to date\n'
  else
    local joined="${components[0]}" index
    for ((index=1; index<${#components[@]}; index++)); do joined+=", ${components[$index]}"; done
    printf '+%s\n' "$joined"
  fi
}

package_family() {
  local first second ignored
  IFS=. read -r first second ignored <<< "$1"
  printf '%s.%s\n' "$first" "$second"
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

lookup_latest_versions() {
  local package_name="$1" installed="$2" versions_file="$TEMP_ROOT/versions.$RANDOM" major same_major absolute
  if ! collect_package_versions "$package_name" "$versions_file"; then
    rm -f "$versions_file"
    printf '|\n'
    return
  fi
  major="${installed%%.*}"
  absolute=$(tail -n 1 "$versions_file")
  same_major=$(awk -F. -v major="$major" '$1 == major {last=$0} END {print last}' "$versions_file")
  rm -f "$versions_file"
  printf '%s|%s\n' "$same_major" "$absolute"
}

plain_text_from_html() {
  sed 's/<span[^>]*material-symbols[^>]*>[^<]*<\/span>//g; s/<[^>]*>/ /g' | \
    sed 's/&amp;/\&/g; s/&quot;/"/g; s/&#39;/'"'"'/g; s/&lt;/</g; s/&gt;/>/g' | \
    tr -s ' '
}

single_line() {
  LC_ALL=C tr -d '\000-\010\013\014\016-\037\177' | \
    tr '\t\r\n' '   ' | tr -s ' ' | sed 's/^ *//; s/ *$//'
}

declare -A NOTE_KEYS=()
declare -A SCRAPED_FILTERS=()

parse_release_note_page() {
  local html_file="$1" destination="$2" flat segments segment note_id text description fixes pair package version key
  flat=$(tr '\n' ' ' < "$html_file" | tr -s ' ')
  segments="$TEMP_ROOT/release-segments.$RANDOM"
  printf '%s\n' "$flat" | awk 'BEGIN {RS="releaseNoteId="} NR>1 {print "releaseNoteId=" $0}' > "$segments"

  while IFS= read -r segment; do
    note_id=$(grep -o '^releaseNoteId=[A-Za-z][A-Za-z0-9]*-[0-9][0-9]*' <<< "$segment" | head -n 1 || true)
    note_id="${note_id#releaseNoteId=}"
    [[ -n "$note_id" ]] || continue

    text=$(printf '%s' "$segment" | plain_text_from_html | single_line)
    description=$(sed "s/.*${note_id}//; s/Fix Version.*//" <<< "$text" | single_line)
    fixes=$(sed 's/.*Fix Version\/ *s: *//' <<< "$text" | sed 's/[A-Z][a-z][a-z]* [0-9][0-9]*, [0-9][0-9][0-9][0-9].*//' | single_line)

    local old_ifs="$IFS" entries=()
    IFS=';'; read -ra entries <<< "$fixes"; IFS="$old_ifs"
    for pair in "${entries[@]}"; do
      pair=$(single_line <<< "$pair")
      package=$(awk '{print $1}' <<< "$pair")
      version=$(awk '{print $2}' <<< "$pair")
      [[ "$package" == *.* && "$version" =~ ^[0-9]+([.][0-9A-Za-z-]+)+$ ]] || continue
      key="$note_id|$package|$version"
      [[ -z "${NOTE_KEYS[$key]:-}" ]] || continue
      NOTE_KEYS[$key]=1
      printf '%s\t%s\t%s\t%s\n' "$note_id" "$package" "$version" "$description" >> "$destination"
    done
  done < "$segments"
  rm -f "$segments"
}

fetch_release_notes_for_filter() {
  local filter="$1" destination="$2" page=1 html_file url count_before count_after
  [[ -z "${SCRAPED_FILTERS[$filter]:-}" ]] || return 0
  SCRAPED_FILTERS[$filter]=1

  while ((page <= 10)); do
    html_file="$TEMP_ROOT/release-page.$RANDOM.html"
    url="${RELEASE_NOTES_BASE}?packageFilter=$(jq -nr --arg value "$filter" '$value|@uri')&typeFilter=All"
    if ((page == 1)); then
      https_get "$url" > "$html_file" 2>/dev/null || { rm -f "$html_file"; return 1; }
    else
      curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --retry 2 --connect-timeout 10 --max-time 30 -fsSL \
        -A "nugetchk/${TOOL_VERSION}" \
        --data-urlencode "packageFilter=$filter" --data "typeFilter=All" --data "PageIndex=$page" \
        "$RELEASE_NOTES_BASE" > "$html_file" 2>/dev/null || { rm -f "$html_file"; return 1; }
    fi

    grep -q 'releaseNoteId=' "$html_file" || { rm -f "$html_file"; return 1; }
    count_before=$(wc -l < "$destination" | tr -d ' ')
    parse_release_note_page "$html_file" "$destination"
    count_after=$(wc -l < "$destination" | tr -d ' ')
    rm -f "$html_file"
    ((count_after > count_before)) || break
    page=$((page + 1))
  done
}

scrape_release_notes() {
  local destination="$1" packages_file="$2" total index=0 package filter parent
  : > "$destination"
  total=$(wc -l < "$packages_file" | tr -d ' ')
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    index=$((index + 1))
    printf '\r  Scraping release notes ... [%d/%d] %s\033[K' "$index" "$total" "$package" >&2
    filter="$package"
    if ! fetch_release_notes_for_filter "$filter" "$destination"; then
      while [[ "$filter" == *.*.* ]]; do
        parent="${filter%.*}"
        [[ "$parent" != "$filter" ]] || break
        filter="$parent"
        fetch_release_notes_for_filter "$filter" "$destination" && break
      done
    fi
  done < "$packages_file"
  printf '\r  Scraping release notes ... done. %s entries extracted.\033[K\n' "$(wc -l < "$destination" | tr -d ' ')" >&2
}

load_or_create_notes() {
  local notes_file="$1" package_names="$2" cache_zip="$3" answer=""
  if [[ "$FORCE_REFRESH" == false && -f "$cache_zip" ]] && command_exists unzip; then
    printf '\n  Cached release notes found: %s\n' "$(basename "$cache_zip")"
    if [[ -t 0 ]]; then
      printf '  Refresh? [y/N] '
      read -r answer || answer=""
    fi
    if [[ ! "$answer" =~ ^[Yy] ]] && unzip -p "$cache_zip" release_notes.tsv > "$notes_file" 2>/dev/null; then
      printf '  Loaded %s release notes from cache.\n' "$(wc -l < "$notes_file" | tr -d ' ')"
      return
    fi
  fi

  scrape_release_notes "$notes_file" "$package_names"
  if command_exists zip; then
    local cache_stage="$TEMP_ROOT/release_notes.tsv"
    cp "$notes_file" "$cache_stage"
    (cd "$TEMP_ROOT" && zip -q -j "$cache_zip" release_notes.tsv) || warn "Could not write release-note cache"
  fi
}

notes_tsv_to_json() {
  local source="$1" destination="$2"
  jq -Rn '[inputs | split("\t") | select(length >= 4) | {
    id: .[0], package: .[1], version: .[2], description: .[3]
  }]' < "$source" > "$destination"
}

build_issue_catalog() {
  local notes_json="$1" destination="$2" terms_json
  terms_json=$(printf '%s\n' "${ISSUE_TERMS[@]}" | jq -R . | jq -s .)
  jq --argjson terms "$terms_json" '[
    .[] as $note |
    [$terms[] | . as $term | select(($note.description | ascii_downcase) | contains($term))] as $matches |
    select(($matches | length) > 0) |
    {
      package: $note.package,
      release_note_id: $note.id,
      fix_version: $note.version,
      matched_keywords: ($matches | unique),
      release_notes_snippet: $note.description
    }
  ]' "$notes_json" > "$destination"
}

highlight_terms() {
  local text="$1"
  if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then printf '%s' "$text"; return; fi

  local lower="${text,,}" term lower_term offset remainder prefix
  local matches=() entry start length finish cursor=0 output=""
  for term in "${ISSUE_TERMS[@]}"; do
    lower_term="${term,,}"; offset=0
    while true; do
      remainder="${lower:$offset}"
      prefix="${remainder%%"$lower_term"*}"
      [[ "$prefix" != "$remainder" ]] || break
      matches+=("$((offset + ${#prefix})):${#term}")
      offset=$((offset + ${#prefix} + ${#term}))
    done
  done
  [[ ${#matches[@]} -gt 0 ]] || { printf '%s' "$text"; return; }

  while IFS= read -r entry; do
    start="${entry%%:*}"; length="${entry##*:}"; finish=$((start + length))
    if ((start >= cursor)); then
      output+="${text:$cursor:$((start-cursor))}"$'\033[30;103m'"${text:$start:$length}"$'\033[0m'
      cursor=$finish
    fi
  done < <(printf '%s\n' "${matches[@]}" | sort -t: -k1,1n)
  output+="${text:$cursor}"
  printf '%s' "$output"
}

build_recommendations() {
  local installed_json="$1" issues_json="$2" same_major_json="$3" absolute_json="$4" destination="$5"
  local package version family same_latest absolute_latest candidates relevant issue fix
  local working="$TEMP_ROOT/recommendations.json"
  printf '[]\n' > "$working"

  while IFS= read -r package_row; do
    package=$(jq -r '.name' <<< "$package_row")
    version=$(jq -r '.version' <<< "$package_row")
    family=$(package_family "$package")
    same_latest=$(jq -r --arg package "$package" '.[$package] // "unknown"' "$same_major_json")
    absolute_latest=$(jq -r --arg package "$package" '.[$package] // "unknown"' "$absolute_json")
    candidates="$TEMP_ROOT/candidates.$RANDOM.json"
    relevant="$TEMP_ROOT/relevant.$RANDOM.jsonl"
    : > "$relevant"

    jq --arg package "$package" --arg family "$family" '[
      .[] | select(
        .package == $package or
        ((.package | split(".") | .[0:2] | join(".")) == $family)
      )
    ]' "$issues_json" > "$candidates"

    while IFS= read -r issue; do
      fix=$(jq -r '.fix_version' <<< "$issue")
      [[ "$fix" != unknown ]] || continue
      if version_is_newer "$fix" "$version"; then
        [[ "$same_latest" == unknown ]] || version_at_least "$same_latest" "$fix" || continue
        printf '%s\n' "$issue" >> "$relevant"
      fi
    done < <(jq -c '.[]' "$candidates")

    local relevant_json="$TEMP_ROOT/relevant.$RANDOM.json"
    jq -s . "$relevant" > "$relevant_json"
    if [[ $(jq 'length' "$relevant_json") -gt 0 ]]; then
      jq --arg package "$package" --arg installed "$version" --arg latest "$same_latest" \
        --arg absolute "$absolute_latest" --slurpfile issues "$relevant_json" '. + [{
          package: $package,
          installed_version: $installed,
          latest_available: $latest,
          absolute_latest: $absolute,
          issues_fixed_in_newer: ($issues[0] | length),
          matched_keywords: ([$issues[0][].matched_keywords[]] | unique),
          details: [$issues[0][] | {
            release_note_id,
            fix_version,
            keywords: .matched_keywords,
            snippet: .release_notes_snippet
          }]
        }]' "$working" > "$working.next"
      mv "$working.next" "$working"
    fi
  done < <(jq -c '.[]' "$installed_json")

  jq 'sort_by(.package)' "$working" > "$destination"
}

write_full_report() {
  local deps_file="$1" app_root="$2" installed="$3" same_major="$4" absolute="$5" recommendations="$6" issue_count="$7"
  jq -n \
    --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg root "$app_root" \
    --arg deps "$(basename "$deps_file")" \
    --slurpfile installed "$installed" \
    --slurpfile same "$same_major" \
    --slurpfile absolute "$absolute" \
    --slurpfile recommendations "$recommendations" \
    --argjson issue_count "$issue_count" '{
      generated_at: $generated,
      app_root: $root,
      deps_file: $deps,
      installed_package_count: ($installed[0] | length),
      packages_with_issues: ($recommendations[0] | length),
      total_issue_entries: $issue_count,
      installed_packages: $installed[0],
      latest_versions_same_major: $same[0],
      latest_versions_absolute: $absolute[0],
      recommendations: $recommendations[0]
    }' > "$REPORT_PATH"
}

print_wrapped_note() {
  local text="$1" width=100 chunk split
  while [[ ${#text} -gt $width ]]; do
    chunk="${text:0:$width}"
    split="${chunk% *}"
    [[ -n "$split" && "$split" != "$chunk" ]] || split="$chunk"
    printf '%s\n' "$(highlight_terms "$split")"
    text="      ${text:${#split}}"
    text="      ${text#"${text%%[! ]*}"}"
  done
  printf '%s\n' "$(highlight_terms "$text")"
}

render_results() {
  local installed="$1" same_major="$2" recommendations="$3" notes_tsv="$4" issue_count="$5"
  local package version latest gap keywords package_lower family note_family note_id note_package note_version note_description

  echo ""
  echo "  RESULTS: $issue_count release notes matched keywords"
  echo ""
  printf '  %-40s %-14s %-14s %-16s %s\n' "PACKAGE" "INSTALLED" "LATEST" "DELTA" "ISSUES FOUND"
  printf '  %-40s %-14s %-14s %-16s %s\n' "-------" "---------" "------" "-----" "------------"

  while IFS= read -r row; do
    package=$(jq -r '.name' <<< "$row")
    version=$(jq -r '.version' <<< "$row")
    latest=$(jq -r --arg package "$package" '.[$package] // "unknown"' "$same_major")
    gap=$(format_version_gap "$version" "$latest")
    keywords=$(jq -r --arg package "$package" '[.[] | select(.package == $package)][0].matched_keywords // [] | if length then join(", ") else "(none)" end' "$recommendations")
    printf '  %-40s %-14s %-14s %-16s %s\n' "$package" "$version" "$latest" "$gap" "$(highlight_terms "$keywords")"

    if [[ "$SHOW_NOTES" == true ]]; then
      package_lower=$(printf '%s' "$package" | tr '[:upper:]' '[:lower:]')
      printf '    Url: %s\n\n' "https://nuget.optimizely.com/packages/${package_lower}/${latest}"
      family=$(package_family "$package")
      while IFS=$'\t' read -r note_id note_package note_version note_description; do
        note_family=$(package_family "$note_package")
        [[ "$note_package" == "$package" || "$note_family" == "$family" ]] || continue
        version_is_newer "$note_version" "$version" || continue
        [[ "$latest" == unknown ]] && continue
        version_at_least "$latest" "$note_version" || continue
        print_wrapped_note "    [${note_version}] ${note_id} ${note_description}"
        printf '    Url: %s\n\n' "https://world.optimizely.com/documentation/Release-Notes/ReleaseNote/?releaseNoteId=${note_id}"
      done < "$notes_tsv"
    fi
  done < <(jq -c '.[]' "$installed")
}

main() {
  local required
  for required in curl find sort awk sed grep tr head tail wc; do
    require_command "$required"
  done
  install_jq_if_needed
  setup_workspace
  resolve_output_dir

  echo ""
  echo "======================================================================"
  echo "  $TOOL_NAME v$TOOL_VERSION"
  echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "======================================================================"

  local deps_file app_root app_name cache_zip installed package_count package_names
  deps_file=$(locate_deps_file)
  app_root=$(cd "$(dirname "$deps_file")" && pwd)
  app_name=$(basename "$deps_file" .deps.json)
  cache_zip="$OUTPUT_DIR/${app_name}_nugetchk_notes.zip"
  installed="$TEMP_ROOT/installed.json"
  package_names="$TEMP_ROOT/package_names.txt"

  log "Using dependency file: $deps_file"
  read_installed_packages "$deps_file" "$installed"
  package_count=$(jq 'length' "$installed")
  if [[ "$package_count" -eq 0 ]]; then
    echo ""
    echo "  No EPiServer/Optimizely packages found. Nothing to check."
    return
  fi
  jq -r '.[].name' "$installed" > "$package_names"
  echo ""
  echo "  Found $package_count EPiServer/Optimizely packages in $(basename "$deps_file")"
  echo ""
  echo "  Querying nuget.optimizely.com for latest versions ..."

  local same_major="$TEMP_ROOT/latest_same_major.json" absolute="$TEMP_ROOT/latest_absolute.json"
  printf '{}\n' > "$same_major"; printf '{}\n' > "$absolute"
  local row package version lookup same absolute_version
  local newer_majors=()
  while IFS= read -r row; do
    package=$(jq -r '.name' <<< "$row")
    version=$(jq -r '.version' <<< "$row")
    lookup=$(lookup_latest_versions "$package" "$version")
    same="${lookup%%|*}"; absolute_version="${lookup##*|}"
    [[ -n "$same" ]] || same="$absolute_version"
    [[ -n "$same" ]] || same=unknown
    [[ -n "$absolute_version" ]] || absolute_version=unknown
    [[ "$same" != unknown ]] || warn "No version data returned for $package"

    jq --arg package "$package" --arg value "$same" '. + {($package): $value}' "$same_major" > "$same_major.next" && mv "$same_major.next" "$same_major"
    jq --arg package "$package" --arg value "$absolute_version" '. + {($package): $value}' "$absolute" > "$absolute.next" && mv "$absolute.next" "$absolute"

    if [[ "$absolute_version" != unknown && "$same" != unknown && "$absolute_version" != "$same" ]]; then
      newer_majors+=("    * $package: v$absolute_version available (current major: ${version%%.*})")
    fi
  done < <(jq -c '.[]' "$installed")

  local notes_tsv="$TEMP_ROOT/release_notes.tsv" notes_json="$TEMP_ROOT/release_notes.json" issues="$TEMP_ROOT/issues.json" recommendations="$TEMP_ROOT/recommendations.json"
  load_or_create_notes "$notes_tsv" "$package_names" "$cache_zip"
  notes_tsv_to_json "$notes_tsv" "$notes_json"
  build_issue_catalog "$notes_json" "$issues"
  cp "$issues" "$ISSUES_PATH"
  build_recommendations "$installed" "$issues" "$same_major" "$absolute" "$recommendations"

  local issue_count recommendation_count
  issue_count=$(jq 'length' "$issues")
  recommendation_count=$(jq 'length' "$recommendations")
  write_full_report "$deps_file" "$app_root" "$installed" "$same_major" "$absolute" "$recommendations" "$issue_count"
  render_results "$installed" "$same_major" "$recommendations" "$notes_tsv" "$issue_count"

  echo ""
  echo "  ----------------------------------------------------------------------"
  echo "  Total packages scanned:       $package_count"
  echo "  Packages with issues:         $recommendation_count"
  echo "  Release notes matched:        $issue_count"
  if [[ ${#newer_majors[@]} -gt 0 ]]; then
    echo ""
    echo "  Newer major versions available:"
    printf '%s\n' "${newer_majors[@]}"
  fi
  echo ""
  echo "  Report:       $REPORT_PATH"
  echo "  Known issues: $ISSUES_PATH"
  echo "======================================================================"
}

[[ "${__TESTING:-}" == 1 ]] || main
