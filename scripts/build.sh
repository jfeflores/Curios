#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${DAYBOOK_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${DAYBOOK_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; fi
arch=$(uname -m)
compile=.build/native
app="${DAYBOOK_APP_PATH:-build/Curios.app}"
compile_flags=()
if [[ "${DAYBOOK_DIAGNOSTICS:-0}" == "1" ]]; then compile_flags+=(-D DAYBOOK_DIAGNOSTICS); fi
mkdir -p "$compile" "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
printf 'Building Curios for %s using %s\n' "$arch" "$sdk"
swiftc -sdk "$sdk" -target "$arch-apple-macosx14.0" -swift-version 5 -parse-as-library -emit-module -emit-library -module-name DaybookCore Sources/DaybookCore/*.swift -emit-module-path "$compile/DaybookCore.swiftmodule" -Xlinker -install_name -Xlinker @rpath/libDaybookCore.dylib -o "$app/Contents/Frameworks/libDaybookCore.dylib"
swiftc -sdk "$sdk" -target "$arch-apple-macosx14.0" -swift-version 5 -parse-as-library -I "$compile" -L "$app/Contents/Frameworks" -lDaybookCore ${compile_flags[@]+"${compile_flags[@]}"} Sources/Daybook/*.swift -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$app/Contents/MacOS/Curios"
cp packaging/Info.plist "$app/Contents/Info.plist"
if [[ -n "${DAYBOOK_BUNDLE_ID:-}" ]]; then /usr/bin/plutil -replace CFBundleIdentifier -string "$DAYBOOK_BUNDLE_ID" "$app/Contents/Info.plist"; fi
swiftc -sdk "$sdk" -swift-version 5 scripts/make-icon.swift -o "$compile/make-icon"
"$compile/make-icon" "$compile/icon.png"
mkdir -p "$compile/Daybook.iconset"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$compile/icon.png" --out "$compile/Daybook.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -s format png -z "$doubled" "$doubled" "$compile/icon.png" --out "$compile/Daybook.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$compile/Daybook.iconset" -o "$app/Contents/Resources/Curios.icns"
codesign --force --sign - "$app/Contents/Frameworks/libDaybookCore.dylib"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
printf '\nBuilt and ad-hoc signed: %s/%s\nOpen with: open "%s"\n' "$PWD" "$app" "$app"
