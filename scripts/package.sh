#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
bash "$project_dir/scripts/build.sh"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/mini-touch-tool.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

ditto "$project_dir/build/Mini Touch Tool.app" "$staging_dir/Mini Touch Tool.app"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname "Mini Touch Tool" -srcfolder "$staging_dir" \
    -format UDZO -ov "$project_dir/build/Mini-Touch-Tool.dmg"
ditto -c -k --sequesterRsrc --keepParent "$project_dir/build/Mini Touch Tool.app" \
    "$project_dir/build/Mini-Touch-Tool.zip"
