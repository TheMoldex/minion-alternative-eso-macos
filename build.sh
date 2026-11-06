#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
destination="${1:-$root/../ESOAddons.app}"
build="$(mktemp -d "${TMPDIR:-/tmp}/esoaddons-build.XXXXXX")"
trap 'rm -rf "$build"' EXIT
core=("$root/Sources/Layout.swift" "$root/Sources/AppUpdates.swift" "$root/Sources/Language.swift" "$root/Sources/Models.swift" "$root/Sources/Catalog.swift" "$root/Sources/Installer.swift" "$root/Sources/Background.swift" "$root/Sources/Operations.swift" "$root/Sources/Snapshots.swift" "$root/Sources/BackupManagement.swift" "$root/Sources/Screenshots.swift")
sdk="$(xcrun --show-sdk-path)"
xcrun swiftc -swift-version 5 -sdk "$sdk" -parse-as-library "${core[@]}" "$root/Tests/AppUpdateChecks.swift" "$root/Tests/FeatureChecks.swift" "$root/Tests/BackupManagementChecks.swift" "$root/Tests/ScreenshotChecks.swift" "$root/Tests/ReadOnlyChecks.swift" "$root/Tests/RecoveryChecks.swift" "$root/Tests/SelfTest.swift" -o "$build/check"
"$build/check" ${ESO_LIVE_TESTS:+--live}
mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources"
xcrun swift "$root/Resources/MakeIcon.swift" "$build/AppIcon.png"
mkdir -p "$build/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$build/AppIcon.png" --out "$build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$build/AppIcon.png" --out "$build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$build/AppIcon.iconset" -o "$destination/Contents/Resources/AppIcon.icns"
xcrun swiftc -swift-version 5 -sdk "$sdk" -O -target arm64-apple-macosx14.0 "${core[@]}" "$root/Sources/ManagerFeatures.swift" "$root/Sources/FeatureViews.swift" "$root/Sources/Preferences.swift" "$root/Sources/ScreenshotViews.swift" "$root/Sources/App.swift" -o "$destination/Contents/MacOS/ESOAddons"
cat > "$destination/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.denstash.ESOAddonsMac</string>
<key>CFBundleName</key><string>ESO Addons</string>
<key>CFBundleDisplayName</key><string>ESO Addons for Mac</string>
<key>CFBundleExecutable</key><string>ESOAddons</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.6</string>
<key>CFBundleVersion</key><string>17</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>ru</string><string>en</string><string>fr</string><string>es</string></array>
</dict></plist>
PLIST
codesign --force --sign "${ESO_SIGNING_IDENTITY:--}" "$destination"
codesign --verify --deep --strict "$destination"
echo "Готово: $destination"
