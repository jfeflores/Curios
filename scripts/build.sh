#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${CURIOS_SDK:-${DAYBOOK_SDK:-$(xcrun --show-sdk-path)}}"
if [[ -z "${CURIOS_SDK:-${DAYBOOK_SDK:-}}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; fi
arch=$(uname -m)
compile=.build/native
app="${CURIOS_APP_PATH:-build/Curios.app}"
compile_flags=()
if [[ "${CURIOS_DIAGNOSTICS:-0}" == "1" ]]; then compile_flags+=(-D CURIOS_DIAGNOSTICS); fi
mkdir -p "$compile" "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources"
printf 'Building Curios for %s using %s\n' "$arch" "$sdk"
swiftc -sdk "$sdk" -target "$arch-apple-macosx14.0" -swift-version 5 -parse-as-library -emit-module -emit-library -module-name CuriosCore Sources/CuriosCore/*.swift -emit-module-path "$compile/CuriosCore.swiftmodule" -Xlinker -install_name -Xlinker @rpath/libCuriosCore.dylib -o "$app/Contents/Frameworks/libCuriosCore.dylib"
swiftc -sdk "$sdk" -target "$arch-apple-macosx14.0" -swift-version 5 -parse-as-library -I "$compile" -L "$app/Contents/Frameworks" -lCuriosCore ${compile_flags[@]+"${compile_flags[@]}"} Sources/Curios/*.swift -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$app/Contents/MacOS/Curios"
# Remove only obsolete generated libraries from a previous local build.
rm -f "$app/Contents/Frameworks/libDaybookCore.dylib"
cp packaging/Info.plist "$app/Contents/Info.plist"
if [[ -n "${CURIOS_BUNDLE_ID:-}" ]]; then /usr/bin/plutil -replace CFBundleIdentifier -string "$CURIOS_BUNDLE_ID" "$app/Contents/Info.plist"; fi
swiftc -sdk "$sdk" -swift-version 5 scripts/make-icon.swift -o "$compile/make-icon"
"$compile/make-icon" "$compile/icon.png"
mkdir -p "$compile/Curios.iconset"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$compile/icon.png" --out "$compile/Curios.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -s format png -z "$doubled" "$doubled" "$compile/icon.png" --out "$compile/Curios.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$compile/Curios.iconset" -o "$app/Contents/Resources/Curios.icns"
codesign --force --sign - "$app/Contents/Frameworks/libCuriosCore.dylib"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
printf '\nBuilt and ad-hoc signed: %s/%s\nOpen with: open "%s"\n' "$PWD" "$app" "$app"
