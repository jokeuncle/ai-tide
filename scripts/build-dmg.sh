#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_stage="$(mktemp -d "$task_root/dist/tide-dmg-XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
ditto "$task_root/dist/AI Tide.app" "$task_stage/AI Tide.app"
ln -s /Applications "$task_stage/Applications"
cp "$task_root/docs/INSTALL.txt" "$task_stage/先读我 - 安装说明.txt"
hdiutil create -volname "AI Tide" -srcfolder "$task_stage" -format UDZO -ov "$task_root/dist/AI-Tide-0.1.0-universal.dmg"
hdiutil verify "$task_root/dist/AI-Tide-0.1.0-universal.dmg"
cd "$task_root/dist"
shasum -a 256 AI-Tide-0.1.0-universal.dmg AI-Tide-macOS.zip > SHA256SUMS.txt
