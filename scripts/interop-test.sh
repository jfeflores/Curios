#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${CURIOS_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${CURIOS_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; fi
build="${CURIOS_TEST_BUILD_DIR:-.build/standalone-tests}"
python="${CURIOS_INTEROP_PYTHON:-python3}"
[[ -f "$build/CuriosCore.swiftmodule" ]] || { printf 'Run scripts/test.sh with the same CURIOS_TEST_BUILD_DIR first.\n' >&2; exit 1; }
"$python" -c 'import cryptography'
swiftc -sdk "$sdk" -swift-version 5 -I "$build" -L "$build" -lCuriosCore Tests/VaultInteropFixture.swift -Xlinker -rpath -Xlinker @executable_path -o "$build/VaultInteropFixture"
profile=$(mktemp -d "$build/interop-XXXXXX")
trap 'rm -rf "$profile"' EXIT
"$build/VaultInteropFixture" "$profile" | "$python" Tests/verify_vault.py
