#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep the review build and all synthetic data separate from the user's app/profile.
CURIOS_APP_PATH=build/review/Curios.app CURIOS_BUNDLE_ID=local.curios.review CURIOS_DIAGNOSTICS=1 scripts/build.sh
sdk="${CURIOS_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${CURIOS_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; fi
swiftc -sdk "$sdk" -swift-version 5 -I .build/native -L build/review/Curios.app/Contents/Frameworks -lCuriosCore Tests/UITestSeed.swift -Xlinker -rpath -Xlinker "$PWD/build/review/Curios.app/Contents/Frameworks" -o .build/native/UITestSeed
mkdir -p .analysis
for scenario in today editor vault; do
  profile=$(mktemp -d "$PWD/.analysis/ui-test-${scenario}-XXXXXX")
  printf 'Isolated UI regression profile (%s): %s\n' "$scenario" "$profile"
  if [[ "$scenario" != "vault" ]]; then .build/native/UITestSeed "$profile"; fi
  CURIOS_DATA_DIR="$profile" CURIOS_UI_TEST_MODE=1 CURIOS_UI_SCENARIO="$scenario" CURIOS_UI_TEST_REPORT="$profile/report.json" \
    "$PWD/build/review/Curios.app/Contents/MacOS/Curios" --snapshot-state "$scenario" > "$profile/runtime.log" 2>&1
  python3 - "$profile/report.json" <<'PY'
import json, sys
with open(sys.argv[1]) as file: report = json.load(file)
print(json.dumps(report, indent=2))
assert report.get('passed') is True, report
PY
done
