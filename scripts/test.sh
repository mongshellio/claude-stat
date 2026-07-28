#!/usr/bin/env bash
# Runs the Claude Code settings regression tests.
#
# Not `swift test`: that needs XCTest or swift-testing, and neither ships with
# the Command Line Tools this project builds against (no Xcode required is a
# stated goal — see README § 설치). So the tests are compiled directly against
# the real source files instead, which keeps them honest — they exercise the
# shipping code, not a copy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

echo "▶ compiling tests"
swiftc -o "$OUT/tests" \
  "$ROOT/Sources/mongshell-menubar/Services/ClaudeSettingsStore.swift" \
  "$ROOT/Sources/mongshell-menubar/Models/ClaudeSettingsModel.swift" \
  "$ROOT/Tests/ClaudeSettingsTests/main.swift"

echo "▶ running"
# MONGSHELL_CLAUDE_SETTINGS is set per-case inside the tests; unset it here so a
# value inherited from the shell can never point them at the real settings file.
env -u MONGSHELL_CLAUDE_SETTINGS "$OUT/tests"
