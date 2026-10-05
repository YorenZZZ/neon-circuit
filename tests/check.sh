#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_app="$task_root/build/NEON Circuit.app"
task_helper="$task_app/Contents/MacOS/neon-cursorctl"
task_fixture="$(mktemp -d "$task_root/build/fixtures.XXXXXX")"
trap 'rm -rf "$task_fixture"' EXIT
for task_binary in "$task_app/Contents/MacOS/NEON Circuit" "$task_helper"; do
  task_arches="$(xcrun lipo -archs "$task_binary")"
  [[ "$task_arches" == "arm64 x86_64" || "$task_arches" == "x86_64 arm64" ]]
done
/usr/bin/codesign --verify --deep --strict "$task_app"
"$task_helper" validate "$task_root/Resources/NEON-CIRCUIT.cape" > "$task_fixture/valid.json"
[[ "$(plutil -extract validated raw "$task_fixture/valid.json")" == true ]]
[[ "$(plutil -extract keys raw "$task_fixture/valid.json")" == 50 ]]
xcrun swiftc -module-cache-path "$task_root/build/module-cache" "$task_root/tests/create-invalid.swift" -o "$task_fixture/create-invalid"
"$task_fixture/create-invalid" "$task_root/Resources/NEON-CIRCUIT.cape" "$task_fixture"
for task_input in "$task_fixture"/*.cape "$task_fixture/missing.cape"; do
  if "$task_helper" validate "$task_input" > "$task_fixture/rejected.json" 2>/dev/null; then
    printf 'Invalid cursor data was accepted: %s\n' "$task_input" >&2; exit 1
  fi
  [[ "$(plutil -extract validated raw "$task_fixture/rejected.json")" == false ]]
done
# Dry-run is pure file/OS inspection, including on unsupported CI machines.
task_dry_code=0
"$task_app/Contents/MacOS/NEON Circuit" --dry-run > "$task_fixture/dry.json" || task_dry_code=$?
[[ "$(plutil -extract cursorAPIsInvoked raw "$task_fixture/dry.json")" == false ]]
task_major="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$task_major" != 27 ]]; then
  [[ "$task_dry_code" != 0 ]]
  [[ "$(plutil -extract fileChecksPassed raw "$task_fixture/dry.json")" == false ]]
fi
printf 'Passed: Universal binaries, signatures, 50-key theme, malformed-data rejection, read-only dry-run.\n'
