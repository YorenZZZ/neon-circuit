#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$task_root/build"
task_app="$task_build/NEON Circuit.app"
task_sdk="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$task_build/bin" "$task_build/module-cache"
for task_arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -sdk "$task_sdk" \
    -target "$task_arch-apple-macosx14.0" \
    -module-cache-path "$task_build/module-cache" \
    -framework AppKit -framework ServiceManagement -framework CryptoKit \
    "$task_root/Sources/main.swift" -o "$task_build/bin/app-$task_arch"
  xcrun clang -O2 -fobjc-arc -isysroot "$task_sdk" \
    -target "$task_arch-apple-macosx14.0" \
    -framework AppKit -framework Foundation -framework CoreGraphics -framework ImageIO \
    "$task_root/Sources/neon-cursorctl.m" -o "$task_build/bin/helper-$task_arch"
done
# Rebuild only this script's generated app, never an installed application.
rm -rf "$task_app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
xcrun lipo -create "$task_build/bin/app-arm64" "$task_build/bin/app-x86_64" \
  -output "$task_app/Contents/MacOS/NEON Circuit"
xcrun lipo -create "$task_build/bin/helper-arm64" "$task_build/bin/helper-x86_64" \
  -output "$task_app/Contents/MacOS/neon-cursorctl"
/usr/bin/plutil -convert binary1 -o "$task_app/Contents/Info.plist" "$task_root/Resources/Info.plist"
printf 'APPL????' > "$task_app/Contents/PkgInfo"
cp "$task_root/Resources/NEON-CIRCUIT.cape" "$task_root/Resources/AppIcon.icns" "$task_app/Contents/Resources/"
cp "$task_root/README.md" "$task_root/README.en.md" "$task_root/LICENSE" "$task_app/Contents/Resources/"
cp -R "$task_root/docs" "$task_app/Contents/Resources/docs"
/usr/bin/codesign --force --sign - "$task_app/Contents/MacOS/neon-cursorctl"
/usr/bin/codesign --force --sign - "$task_app"
/usr/bin/codesign --verify --deep --strict "$task_app"
"$task_app/Contents/MacOS/neon-cursorctl" validate "$task_app/Contents/Resources/NEON-CIRCUIT.cape"
printf 'Built Universal, ad hoc signed preview: %s\n' "$task_app"
printf 'Build does not launch the app or change any cursors.\n'
