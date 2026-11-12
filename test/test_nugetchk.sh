#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export __TESTING=1
# shellcheck source=../nugetchk.sh
source "$ROOT_DIR/nugetchk.sh"

passed=0
failed=0

pass() { printf 'PASS: %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=$((failed + 1)); }

assert_equal() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name (expected '$expected', got '$actual')"
  fi
}

assert_true() {
  local name="$1"; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

assert_false() {
  local name="$1"; shift
  if "$@"; then fail "$name"; else pass "$name"; fi
}

assert_true "newer major" version_is_newer 13.0.0 12.99.99
assert_true "newer minor" version_is_newer 12.23.0 12.22.9
assert_true "newer patch" version_is_newer 12.22.10 12.22.9
assert_false "equal is not newer" version_is_newer 12.22.9 12.22.9
assert_false "older is not newer" version_is_newer 12.21.9 12.22.0
assert_equal "major delta" "+1maj" "$(format_version_gap 12.34.4 13.6.0)"
assert_equal "minor delta" "+3min" "$(format_version_gap 12.21.6 12.24.0)"
assert_equal "patch delta" "+3pat" "$(format_version_gap 4.4.2 4.4.5)"
assert_equal "up-to-date delta" "up to date" "$(format_version_gap 12.22.9 12.22.9)"
assert_equal "ahead delta" "ahead" "$(format_version_gap 13.1.0 13.0.2)"
assert_equal "unknown delta" "?" "$(format_version_gap 12.22.9 unknown)"
assert_equal "version normalization" "12 22 9" "$(version_parts 12.22.9-beta+build.1)"
assert_equal "default application root" "/app" "$DEFAULT_APP_ROOT"
assert_equal "tool version" "1.1.0" "$TOOL_VERSION"

printf '\nTests passed: %d\nTests failed: %d\n' "$passed" "$failed"
[[ "$failed" -eq 0 ]]
