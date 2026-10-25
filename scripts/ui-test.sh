#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep the review build and all synthetic data separate from the user's app/profile.
DAYBOOK_APP_PATH=build/review/Curios.app DAYBOOK_BUNDLE_ID=local.curios.review DAYBOOK_DIAGNOSTICS=1 scripts/build.sh
mkdir -p .analysis
for scenario in today editor; do
  profile=$(mktemp -d "$PWD/.analysis/ui-test-${scenario}-XXXXXX")
  printf 'Isolated UI regression profile (%s): %s\n' "$scenario" "$profile"
  DAYBOOK_DATA_DIR="$profile" DAYBOOK_UI_TEST_MODE=1 DAYBOOK_UI_SCENARIO="$scenario" DAYBOOK_UI_TEST_REPORT="$profile/report.json" \
    "$PWD/build/review/Curios.app/Contents/MacOS/Curios" --snapshot-state "$scenario" > "$profile/runtime.log" 2>&1
  python3 - "$profile/report.json" <<'PY'
import json, sys
with open(sys.argv[1]) as file: report = json.load(file)
print(json.dumps(report, indent=2))
assert report.get('passed') is True, report
PY
done
