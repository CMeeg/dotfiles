#!/usr/bin/env bash
set -euo pipefail

# Tests for lib/gitkraken.sh. No network: only the pure helpers are tested.
# Usage: bash tests/gitkraken.test.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

setup() {
  # shellcheck source=../lib/gitkraken.sh
  source "$REPO_ROOT/lib/gitkraken.sh"
}

# Each test runs in its own subshell, so exit only ends that test.
fail() {
  echo "  $1"
  exit 1
}

test_version_from_url_parses_redirect() {
  local v
  v="$(gitkraken_version_from_url "https://release.gitkraken.dev/gkd/production/normal/linux/x64/12.6.2/3LdymkbiGLlvUgLoGwehfDP0Qeo/gitkraken-amd64.deb")" || fail "returned non-zero"
  [ "$v" = "12.6.2" ] || fail "got '$v'"
}

test_version_from_url_rejects_unversioned_url() {
  local v rc=0
  v="$(gitkraken_version_from_url "https://release.gitkraken.com/linux/gitkraken-amd64.deb")" || rc=$?
  [ "$rc" -eq 1 ] || fail "expected exit 1, got $rc"
  [ -z "$v" ] || fail "expected no output, got '$v'"
}

test_needs_update_when_versions_differ() {
  gitkraken_needs_update 12.6.2 12.7.0 || fail "expected 0"
}

test_needs_update_false_when_equal() {
  local rc=0
  gitkraken_needs_update 12.6.2 12.6.2 || rc=$?
  [ "$rc" -eq 1 ] || fail "expected 1, got $rc"
}

test_needs_update_ignores_debian_revision() {
  local rc=0
  gitkraken_needs_update 12.6.2-1 12.6.2 || rc=$?
  [ "$rc" -eq 1 ] || fail "expected 1, got $rc"
}

main() {
  local tests name
  tests="$(declare -F | awk '{print $3}' | grep '^test_')"
  for name in $tests; do
    if (setup && "$name"); then
      echo "PASS $name"
    else
      echo "FAIL $name"
      FAILURES=$((FAILURES + 1))
    fi
  done
  [ "$FAILURES" -eq 0 ]
}

main "$@"
