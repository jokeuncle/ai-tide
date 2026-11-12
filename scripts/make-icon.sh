#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_icon_dir="$(mktemp -d "$task_root/dist/tide-icon-XXXXXX")"
trap 'rm -rf "$task_icon_dir"' EXIT
mkdir -p "$task_icon_dir/Tide.iconset"
for task_size in 16 32 128 256 512; do
  /usr/bin/sips -z "$task_size" "$task_size" "$task_root/Sources/Tide/Resources/app-icon.png" --out "$task_icon_dir/Tide.iconset/icon_${task_size}x${task_size}.png" >/dev/null
  task_double=$((task_size * 2))
  /usr/bin/sips -z "$task_double" "$task_double" "$task_root/Sources/Tide/Resources/app-icon.png" --out "$task_icon_dir/Tide.iconset/icon_${task_size}x${task_size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$task_icon_dir/Tide.iconset" -o "$task_root/dist/Tide.icns"
