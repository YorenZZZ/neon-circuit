#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_app="$task_root/build/NEON Circuit.app"
task_kind="${1:-preview}"
if [[ "$task_kind" != preview && "$task_kind" != signed ]]; then
  printf 'Usage: %s [preview|signed]\n' "$0" >&2; exit 2
fi
[[ -d "$task_app" ]] || { printf 'Run scripts/build.sh first.\n' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$task_app"
if [[ "$task_kind" == signed ]]; then
  /usr/sbin/spctl --assess --type execute "$task_app"
  xcrun stapler validate "$task_app"
fi
task_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$task_app/Contents/Info.plist")"
task_name="NEON-Circuit-$task_version-$task_kind-universal"
task_stage="$(mktemp -d "$task_root/build/package.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
mkdir -p "$task_root/dist"
/usr/bin/ditto --norsrc "$task_app" "$task_stage/NEON Circuit.app"
cp "$task_root/README.md" "$task_root/README.en.md" "$task_root/LICENSE" "$task_stage/"
# Reuse the complete manual embedded in the app instead of storing every
# illustration twice inside the disk image. Relative README links still work.
ln -s 'NEON Circuit.app/Contents/Resources/docs' "$task_stage/docs"
ln -s /Applications "$task_stage/Applications"
if [[ "$task_kind" == preview ]]; then
  printf 'Preview: ad hoc signature only; no Developer ID or Apple notarization.\n' > "$task_stage/PREVIEW-NOT-NOTARIZED.txt"
fi
/usr/bin/ditto -c -k --norsrc --keepParent "$task_stage/NEON Circuit.app" "$task_root/dist/$task_name.zip"
/usr/bin/hdiutil create -ov -format UDZO -volname "NEON Circuit" \
  -srcfolder "$task_stage" "$task_root/dist/$task_name.dmg"
(cd "$task_root/dist" && shasum -a 256 "$task_name.zip" "$task_name.dmg" > "$task_name.SHA256SUMS")
printf 'Packaged %s (not uploaded).\n' "$task_name"
