# Testing and verification

## Unified filters check — October 4, 2026

The small shared core suite passed: 22 tests, 0 failures, including a regression check that expanding distance reveals Maple Granola without a hidden shortcut cap. The single Simulator test `testDiscoveryScreenshotAndEmptyFilterResults` passed: 1 test, 0 failures. Filter screenshots were exported and visually reviewed; the updated app was reopened in Simulator. Result: `work/UnifiedFilters-20261004.xcresult`; logs: `work/unified-filters-core.log`, `work/unified-filters-ui.log`. Full UI flow and device builds were not rerun.

## Verified on October 3, 2026

| Check | Result |
| --- | --- |
| Shared core on macOS | 21 tests passed, 0 failures |
| Hosted core on iPhone 16 / iOS 18.5 | 21 tests passed, 0 failures |
| iPhone Simulator UI integration | 4 tests passed, 0 failures |
| Complete four-seller demo | Passed; $7.75 paid, $14.63 saved, 6.1 lb rescued |
| iPhone Release compilation | Unsigned arm64 device build passed |
| Swift formatting | Strict bundled swift-format lint passed |

The complete successful run is `work/RescueTests-20261003-233936.xcresult`; its command output is `work/acceptance-tests.log`. Subsequent map positions, native tab-bar appearance and sticky-footer styling were verified with the targeted discovery/map/filter UI check. Device compilation was repeated after those visual changes. No physical iPhone installation or real payment was performed.

Reviewed screenshots are saved in `docs/screenshots/`: Discover, listing, cart, pickup plan, payment, impact, profile, messages, chat, seller editor and map. Profile is the initial fixture state; impact/cart screenshots show the four-seller run. Tests capture representative scroll positions, not every section of every long screen. The latest map/profile/discovery images include the final native tab-bar appearance.

## Requirements

Xcode 16.4+, its command-line tools, and an installed iOS Simulator runtime. Development target is iOS 17+. The implementation was built using Swift 6.1.2, Swift 5 language mode, and the iOS 18.5 SDK. There are no packages to fetch or backend credentials to configure.

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
  CODE_SIGNING_ALLOWED=NO test
```

Unsigned device compilation:

```sh
xcodebuild -project Rescue.xcodeproj -scheme Rescue -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath work/DeviceBuild \
  CODE_SIGNING_ALLOWED=NO build
```

An unsigned device build verifies the iPhone target compiles; it does not install on hardware. Select a development team in Xcode before running on your connected iPhone. Automatic signing is enabled in the project.

## Coverage

The 21 core tests exercise meaningful state and arithmetic invariants:

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

The 4 UI tests cover:

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

Automated coverage targets the local hackathon demo. Live MapKit tile loading, real network/backend, actual payments, push delivery, camera recognition and physical-device signing are outside the mock implementation. Dynamic Type, VoiceOver and different iPhone sizes should also receive manual review before a production release. The app uses scaled fonts and native accessibility controls, with reduced-motion support for the shared spring animation.
