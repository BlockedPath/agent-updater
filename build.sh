#!/usr/bin/env bash
# Build "Agent Updater.app" and install it in ~/Applications.
#   ./build.sh          build + install
#   ./build.sh --open   build + install + launch
#   ./build.sh --bundle-only   build .build/app/Agent Updater.app without installing
#   ./build.sh --release       build and zip it into dist/ for a GitHub release (ad-hoc signed)
set -euo pipefail
cd "$(dirname "$0")"

app_name="Agent Updater"
build_dir=.build/app
app="$build_dir/$app_name.app"
dest="$HOME/Applications/$app_name.app"

swift build -c release
bin=$(swift build -c release --show-bin-path)/AgentUpdater

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/AgentUpdater"

# App icon: AppIcon.png (1024 px, made with Codex's image generation) when present, otherwise
# the drawn fallback from make-icon.swift. Converted once and cached.
icns=.build/AppIcon.icns
source_icon=AppIcon.png
[[ -f $source_icon ]] || source_icon=make-icon.swift
if [[ ! -f $icns || $source_icon -nt $icns ]]; then
  iconset=.build/AppIcon.iconset
  rm -rf "$iconset" && mkdir -p "$iconset"
  if [[ $source_icon == AppIcon.png ]]; then cp AppIcon.png .build/icon-1024.png; else swift make-icon.swift .build/icon-1024.png; fi
  for s in 16 32 128 256 512; do
    sips -z $s $s .build/icon-1024.png --out "$iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) .build/icon-1024.png --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$icns"
fi
cp "$icns" "$app/Contents/Resources/AppIcon.icns"
# The CLI the app drives, plus its OS-support data, ship inside the app.
cp update-agents agent-platforms.json "$app/Contents/Resources/"
chmod +x "$app/Contents/Resources/update-agents"

cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Agent Updater</string>
  <key>CFBundleDisplayName</key><string>Agent Updater</string>
  <key>CFBundleIdentifier</key><string>dev.thoughtloop.AgentUpdater</string>
  <key>CFBundleExecutable</key><string>AgentUpdater</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>VERSION_PLACEHOLDER</string>
  <key>CFBundleVersion</key><string>BUILD_PLACEHOLDER</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

version=$(cat VERSION)
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)
sed -i '' -e "s/VERSION_PLACEHOLDER/$version/" -e "s/BUILD_PLACEHOLDER/$build/" "$app/Contents/Info.plist"

codesign --force --sign - "$app" >/dev/null
[[ ${1:-} == --bundle-only ]] && exit 0
if [[ ${1:-} == --release ]]; then
  mkdir -p dist
  zip="dist/Agent-Updater-$version.zip"
  rm -f "$zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
  shasum -a 256 "$zip"
  exit 0
fi
mkdir -p "$HOME/Applications"
rm -rf "$dest"
cp -R "$app" "$dest"
echo "Installed $dest"

[[ ${1:-} == --open ]] && open "$dest"
exit 0
