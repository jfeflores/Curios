#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${DAYBOOK_SDK:-$(xcrun --show-sdk-path)}"
# Some beta CLT releases ship incomplete SwiftUI macros and mismatched ManifestAPI
# interfaces. Use an existing stable SDK, without modifying/installing any toolchain.
if [[ -z "${DAYBOOK_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; fi
arch=$(uname -m)
build="${DAYBOOK_TEST_BUILD_DIR:-.build/standalone-tests}"
mkdir -p "$build"
swiftc -sdk "$sdk" -target "$arch-apple-macosx14.0" -swift-version 5 -parse-as-library -enable-testing -emit-module -emit-library -module-name DaybookCore Sources/DaybookCore/*.swift -emit-module-path "$build/DaybookCore.swiftmodule" -Xlinker -install_name -Xlinker @rpath/libDaybookCore.dylib -o "$build/libDaybookCore.dylib"
python3 - "$build/main.swift" <<'PY'
import pathlib, re, sys
suites, cases = [], []
for index, path in enumerate(sorted(pathlib.Path('Tests/DaybookCoreTests').glob('*.swift'))):
    source = path.read_text()
    name = re.search(r'final class (\w+): XCTestCase', source).group(1)
    methods = re.findall(r'func (test\w+)\(\)(?: throws)?', source)
    suites.append(f'let suite{index} = {name}()')
    cases += [(f'{name}.{method}', f'suite{index}.{method}') for method in methods]
assert cases, 'No tests discovered'
lines = ['import Foundation', 'import Darwin'] + suites + ['var passed = 0', 'let tests: [(String, () throws -> Void)] = [']
lines += [f'("{label}", {method}),' for label, method in cases]
lines += [']', 'for (name, run) in tests {', 'let before = failureCount', 'do { try run() } catch { XCTFail("Unexpected error: \\(error)") }', 'if failureCount == before { passed += 1; print("PASS \\(name)") }', '}']
lines += [f'print("\\(passed)/{len(cases)} tests passed; \\(failureCount) assertion failures")', 'exit(failureCount == 0 ? 0 : 1)']
pathlib.Path(sys.argv[1]).write_text('\n'.join(lines) + '\n')
PY
swiftc -sdk "$sdk" -target "$arch-apple-macosx14.0" -swift-version 5 -D DAYBOOK_STANDALONE_TESTS -I "$build" -L "$build" -lDaybookCore Tests/StandaloneSupport.swift Tests/DaybookCoreTests/*.swift "$build/main.swift" -Xlinker -rpath -Xlinker @executable_path -o "$build/DomainTests"
"$build/DomainTests"
swiftc -sdk "$sdk" -target "$arch-apple-macosx14.0" -swift-version 5 -parse-as-library -I "$build" -L "$build" -lDaybookCore Sources/Daybook/AppStore.swift Sources/Daybook/Integrations.swift Sources/Daybook/UICheckboxSelfTest.swift Tests/AppIntegrationSmoke.swift -Xlinker -rpath -Xlinker @executable_path -o "$build/AppIntegrationSmoke"
"$build/AppIntegrationSmoke"
