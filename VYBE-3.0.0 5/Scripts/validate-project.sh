#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v swiftc >/dev/null || { echo "swiftc is required" >&2; exit 1; }
command -v plutil >/dev/null || { echo "plutil is required" >&2; exit 1; }
plutil -lint VYBE.xcodeproj/project.pbxproj
for source in VYBE/*.swift; do
  echo "Parsing $source"
  swiftc -frontend -parse "$source"
done
if command -v swift-format >/dev/null; then
  swift-format lint --strict VYBE/VYBENextSystems.swift
fi
python3 - <<'PY'
from pathlib import Path
project = Path('VYBE.xcodeproj/project.pbxproj').read_text()
assert 'path = VYBENextSystems.swift;' in project, 'New systems source is missing from the Xcode project'
assert 'A10000000000000000000056' in project, 'New systems source is missing from the Sources build phase'
source = Path('VYBE/VYBENextSystems.swift').read_text()
for name in ['DesktopSystemPanel', 'CommandSystemPanel', 'IntelligenceSystemPanel', 'ControlSystemPanel', 'FlowSystemPanel', 'WorkspaceSystemPanel', 'StudioSystemPanel', 'UtilitiesSystemPanel']:
    assert name in source, f'Missing system panel: {name}'
print('Static project checks passed.')
PY
if [[ "$(uname -s)" == "Darwin" ]]; then
  xcodebuild -project VYBE.xcodeproj -target VYBE -configuration Debug -sdk macosx CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build
else
  echo "Skipping xcodebuild: this host is not macOS. The macOS GitHub Actions workflow performs the real Xcode build."
fi
