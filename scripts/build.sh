#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_dir/build"
app_dir="$build_dir/Mini Touch Tool.app"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swift "$project_dir/scripts/make-icon.swift" "$build_dir/AppIcon.iconset"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
xcrun clang -O2 -Wall -Wextra -Wno-unused-parameter -fobjc-arc \
    -mmacosx-version-min=15.0 -c "$project_dir/Sources/Trackpad.m" -o "$build_dir/Trackpad.o"
xcrun swiftc -O -swift-version 5 -warnings-as-errors \
    -target arm64-apple-macosx15.0 \
    -import-objc-header "$project_dir/Sources/Trackpad.h" \
    "$project_dir"/Sources/*.swift "$build_dir/Trackpad.o" \
    -framework AppKit -framework ApplicationServices -framework ServiceManagement \
    -o "$app_dir/Contents/MacOS/MiniTouchTool"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - --identifier com.peitalin.MiniTouchTool "$app_dir"
codesign --verify --strict "$app_dir"
printf '%s\n' "$app_dir"
