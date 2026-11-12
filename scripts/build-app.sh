#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
mode="${1:---universal}"
if [ "$mode" != "--universal" ] && [ "$mode" != "--native" ]; then
  echo "Usage: scripts/build-app.sh [--universal|--native]" >&2
  exit 2
fi
mkdir -p dist
task_app="$task_root/dist/AI Tide.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
if [ "$mode" = "--universal" ]; then
  swift build -c release --arch arm64
  swift build -c release --arch x86_64
  task_arm_bin="$(swift build -c release --arch arm64 --show-bin-path)"
  task_intel_bin="$(swift build -c release --arch x86_64 --show-bin-path)"
  /usr/bin/lipo -create "$task_arm_bin/Tide" "$task_intel_bin/Tide" -output "$task_app/Contents/MacOS/Tide"
  task_resources="$task_arm_bin/AITide_Tide.bundle"
else
  swift build -c release
  task_native_bin="$(swift build -c release --show-bin-path)"
  cp "$task_native_bin/Tide" "$task_app/Contents/MacOS/Tide"
  task_resources="$task_native_bin/AITide_Tide.bundle"
fi
cp -R "$task_resources" "$task_app/Contents/Resources/"
"$task_root/scripts/make-icon.sh"
cp "$task_root/dist/Tide.icns" "$task_app/Contents/Resources/Tide.icns"
# SwiftPM's Bundle.module lookup in a bundled executable also checks the .app root.
cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>AI Tide</string>
<key>CFBundleDisplayName</key><string>潮汐</string>
<key>CFBundleIdentifier</key><string>studio.aitide.desktop</string>
<key>CFBundleExecutable</key><string>Tide</string>
<key>CFBundleIconFile</key><string>Tide.icns</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
if [ -n "${TIDE_SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$TIDE_SIGN_IDENTITY" "$task_app"
else
  codesign --force --sign - "$task_app"
  echo "Local ad-hoc signature only. Public distribution requires Developer ID signing and notarization."
fi
codesign --verify --deep --strict "$task_app"
ditto -c -k --keepParent "$task_app" "$task_root/dist/AI-Tide-macOS.zip"
"$task_app/Contents/MacOS/Tide" --check-resources
echo "Built: $task_app"
file "$task_app/Contents/MacOS/Tide"
