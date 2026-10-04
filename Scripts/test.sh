#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
swift test --scratch-path work/swift-build
device_id="${RESCUE_SIMULATOR_ID:-}"
if [ -z "$device_id" ]; then
    device_id="$(xcrun simctl list devices available -j | python3 -c 'import sys,json; data=json.load(sys.stdin); print(next((d["udid"] for group in data["devices"].values() for d in group if "iPhone" in d["name"] and d["isAvailable"]), ""))')"
fi
if [ -z "$device_id" ]; then
    echo "No iPhone Simulator runtime installed. Install one in Xcode Settings → Components." >&2
    exit 1
fi
result="work/RescueTests-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project Rescue.xcodeproj -scheme Rescue \
    -destination "platform=iOS Simulator,id=$device_id" \
    -derivedDataPath work/DerivedData -resultBundlePath "$result" \
    -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
echo "Results: $result"
