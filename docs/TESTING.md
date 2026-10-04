# Testing and verification

## Current backend and integration checks

The October 4 implementation includes an isolated local database suite plus Swift tests for
HTTP serialization, account cache/outbox isolation, offline launch, retry IDs, permanent rejection,
metadata budget, and arbitrary seller/location planning. Existing fixture UI flows are retained.

```sh
cd MHacksDB
npm test
npm run load-test
```

Both commands create an isolated `rescue-test-*` database, seed it through owner-only tooling,
exercise authenticated APIs, and republish with `--delete-data=never`. They leave records intact
for inspection. The load test uses 2,000 packages and checks continuation after 500 candidates.

Connected Simulator flows require the database, media and separate simulator processes from
MHacksDB/README.md. Simulator builds need ad-hoc signing for Keychain access; an unsigned
Simulator app cannot store sessions. No development-team enrollment is required for local signing.

```sh
TEST_RUNNER_RESCUE_CONNECTED_TESTS=1 xcodebuild -project Rescue.xcodeproj -scheme Rescue \
  -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath work/DerivedData \
  -parallel-testing-enabled NO \
  -only-testing:RescueUITests/RescueUITests/testConnectedSellerPublishesBuyerReservesAndPays \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test

RESCUE_LIVE_BACKEND=1 swift test --scratch-path work/swift-build \
  --filter BackendTests/testLiveSwiftBootstrap
```

The connected test publishes as Riley, restarts as the buyer, discovers the new item, reserves,
coordinates, starts the run, goes through arrival/handoff/verification/payment and finishes with
server-derived demo impact. Run Simulator tests serially; separate xcodebuild processes must not
share the same Simulator concurrently. Ordinary regression runs skip connected opt-in tests.

Current evidence logs are under ignored `work/`: `backend-tests.log`, `backend-load-test.log`,
`core-tests.log`, `swift-live.log`, `connected-ui.log`, `ios-tests.log`, `device-build.log`,
and `format.log`. The final connected result is `ConnectedHandoff.xcresult`; the fixture
regression result is `RegressionFinal.xcresult`. The final core run passed 29 tests with the live
opt-in test skipped, and the unsigned device build passed. The isolated backend suite and actual
server restart both preserved receipts, impact and subsequent unique IDs. The earlier 2,000-package
load run passed bounded scanning and pagination. Fixture regression predates the final small
follow/search/history presentation additions; the final device build and connected test cover the
final source.

## Requirements

Xcode 16.4+, its command-line tools, and an installed iOS Simulator runtime. Development target is iOS 17+. The implementation was built using Swift 6.1.2, Swift 5 language mode, and the iOS 18.5 SDK. There are no Swift packages to fetch. Backend mode requires the local services and provisioned demo sessions.

## One command

From the repository root:

```sh
./Scripts/test.sh
```

This runs the shared core suite on macOS, then both hosted iOS unit tests and UI tests on the first available iPhone Simulator. To choose a specific device:

```sh
RESCUE_SIMULATOR_ID=<simulator-UDID> ./Scripts/test.sh
```

Get IDs with `xcrun simctl list devices available`. Each run produces a timestamped `work/RescueTests-*.xcresult`. Open the result in Xcode to inspect failures, screenshots, and recorded UI actions. `work/` is ignored by Git. Tests launch the actual app with `--uitesting`: onboarding is skipped and mock delays are 50ms; cart, confirmations, handoff and payment still go through the normal product flow.

## Targeted checks

Core changes:

```sh
swift test --scratch-path work/swift-build
```

One UI test (include target, class, and method):

```sh
xcodebuild -project Rescue.xcodeproj -scheme Rescue \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath work/DerivedData -parallel-testing-enabled NO \
  -only-testing:RescueUITests/RescueUITests/testDiscoverToFourSellerPickupAndImpact \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Unsigned device compilation:

```sh
xcodebuild -project Rescue.xcodeproj -scheme Rescue -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath work/DeviceBuild \
  CODE_SIGNING_ALLOWED=NO build
```

An unsigned device build verifies the iPhone target compiles; it does not install on hardware. Select a development team in Xcode before running on your connected iPhone. Automatic signing is enabled in the project.

## Coverage

The original 21 fixture core tests exercise meaningful state and arithmetic invariants:

- Exact source catalog, integer money, unique reservations and invalid IDs.
- Multiple items grouped into one seller stop; empty plans cannot start.
- Confirmation gating, counteroffer acceptance/alternative, downstream rescheduling, different route preferences.
- Cart edits invalidate draft confirmations; active runs lock cart and route edits.
- Full four-seller arrival → verification → payment → impact flow.
- Concurrent/duplicate payment does not double-charge; invalid phase transitions are rejected.
- Reporting an issue skips payment and excludes the items from impact.
- Fresh Check, correct seller chat, search and shared filters.
- Seller publishing requires all four safety confirmations.
- Reset restores fixtures and rejects delayed replies from the prior session.
- Two separate runs with the same seller produce distinct receipt IDs.

The 4 fixture UI tests cover:

1. Discover → listing → search/reserve three additional items → cart → route → seller coordination/counteroffer → all four pickups/payments → exact impact → profile.
2. Chat input, correct Sam pinned listing, outgoing message and local reply.
3. Sell photo/scan mock, disabled publish until safety confirmation, successful local listing.
4. Discover rendering, Tomorrow-only filtering and the map's empty state.

These tests save named screenshots as XCTest attachments. Screenshot inspection checks layout, cropping and native safe areas; the tests are not pixel-diff assertions against Figma.

## Visual review

Export attachments for local inspection:

```sh
xcrun xcresulttool export attachments \
  --path work/RescueTests-<timestamp>.xcresult --output-path work/screenshots
```

The generated manifest maps file names to Discover, listing, cart, pickup plan, coordinated plan, arrival, verification, payment, completed impact, filters/map and published-listing screenshots. Compare them with the visual contract in `DESIGN.md`. Allow UIKit's presentation transition to settle before taking a screenshot.

## Practical boundaries

Automated coverage includes the local backend and Simulator integration. Live MapKit tiles, cloud hosting, actual payments, push delivery, camera recognition and physical-device signing remain outside this local implementation. Dynamic Type, VoiceOver and different iPhone sizes should also receive manual review before a production release. The app uses scaled fonts and native accessibility controls, with reduced-motion support for the shared spring animation.
