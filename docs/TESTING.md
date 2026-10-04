# Testing and verification

## Combined UI/backend merge verification — October 4, 2026

The combined shared core suite ran 31 tests with 1 opt-in live test skipped and 0 failures. The app compiled with ad-hoc Simulator signing and the single fixture test `testDiscoveryScreenshotAndEmptyFilterResults` passed. Connected backend services and firmware were preserved but were not deployed or retested in this merge pass. Logs: `work/rebase-resolution-core.log`, `work/merged-ui-backend-check.log`; result: `work/MergedUIBackend-20261004.xcresult`.

## UI validation before backend integration — October 4, 2026

The UI branch's core suite passed 22 tests, including the distance expansion regression. One focused fixture Simulator check passed for unified filters. These results predate the combined backend/UI resolution. Results and logs: `work/UnifiedFilters-20261004.xcresult`, `work/unified-filters-core.log`, `work/unified-filters-ui.log`.

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

Connected Simulator tests explicitly use `--local-backend`; normal app launches select
Maincloud and show real sign-in when no cloud session is present.
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

Automated coverage includes the local backend and Simulator integration. Live MapKit tiles, actual payments, push delivery, camera recognition and physical-device signing remain outside the automated coverage. Cloud authentication verification is described below. Dynamic Type, VoiceOver and different iPhone sizes should also receive manual review before a production release. The app uses scaled fonts and native accessibility controls, with reduced-motion support for the shared spring animation.

## Cloud authentication verification

`OAuthTests` checks the RFC 7636 PKCE vector, callback state/destination/duplicate guards,
and token response issuer/project/audience/nonce/expiry binding. BackendTests verifies
refreshed-token transport, rejects a cross-account session provider, and clears visible
private data on sign-out. `MHacksDB/scripts/auth-test.mjs` tests registration claim restrictions.
The cloud `register_profile` endpoint rejects forged and non-app administrative tokens.
`RescueUITests/testCloudLaunchRequiresSignIn` verifies the cloud sign-in screen without
using local demo credentials. Run on a Simulator with no saved cloud session.

A real Google login is a manual verification: sign in, confirm one `users` and
`user_identities` row, sign out and in again, and confirm no duplicate rows. Then relaunch
and verify restoration. Expiry/refresh and successful server registration need live
provider verification in addition to the deterministic tests; do not claim success from
compilation or the sign-in screen alone.

Cloud catalog verification (October 4): `seed_cloud_catalog` installed 200 listings and
12 sample profiles alongside the existing authenticated account. A second owner call did
not duplicate records; an anonymous call was rejected with `unauthorized`. Simulator
verification showed populated Discover cards and bundled sample photos using the saved
Google session. Local simulation remained disabled on Maincloud.

Location integration: the core suite passed 36 tests (1 live-backend test skipped),
including distance recalculation, nearby filtering, and invalid coordinate rejection.
`testManualLocationPickerOpens` passed in Simulator; the unsigned iPhone Release build
passed. A normal cloud launch visibly displayed the Gusto When In Use permission prompt.
Actual device movement, reverse-geocoded names, and live Apple place search still need
physical-device/network verification. Simulator location was set to Ann Arbor.

Deterministic `--uitesting` runs do not resume GPS or apply device coordinates to fixture listing distances; location recalculation is verified in core tests. Normal launches use the live location adapter.

`testInteractiveMarketplaceMapAndLocationPicker` exercises native Apple Maps panning, Search this area, the recenter control, and opening and dismissing the anchored location dropdown. It uses fixture inventory but live MapKit rendering; cloud query results and GPS movement require an authenticated session/device.

`testInlineDiscoverySearchAndClear` verifies inline matching results, absent fake history, clearing, the empty-results state, and cancellation back to Discover. Pickup and connected-backend helpers now type directly into Discover rather than opening a search sheet.

`testMapAddressSearchPinsSelection` uses live Apple Maps address search, selects a result, and checks that the manual-location pin appears. It requires network access to Apple Maps.

## Cart confirmation — October 4, 2026

Saved cloud carts are tested with two buyers adding the same listing without any reservation or draft run. Repeated adds keep one cart entry. Explicit plan confirmation creates a hold; a competing cart confirmation fails and rolls back its claims. The isolated backend suite also checks release, expiry, payment, and preservation through republishing. The core suite passed 36 tests with one opt-in test skipped; `testDiscoverToFourSellerPickupAndImpact` passed in Simulator with the Add to cart and Confirm & plan pickups flow. Logs: `/tmp/gusto-cart-core.log`, `/tmp/gusto-cart-backend.log`, `/tmp/gusto-cart-ui.log`.

## Messages refresh — October 4, 2026

`testGustoWelcomeMessage` passes opening the built-in platform note and returning to the inbox. `testChatComposerAndCorrectPinnedItem` passes opening a seller chat, preserving its listing context, sending a message, and receiving the fixture reply. Simulator logs: `/tmp/gusto-messages-ui.log` and `/tmp/gusto-messages-chat.log`.

## Scan / inventory — October 4, 2026

The core suite passes 39 tests (one opt-in test skipped), including private inventory save without publishing/reserving and item/device/time/range isolation for three-day storage summaries. The isolated backend suite passes private scan access, sensor sample validation, explicit seller attestations, publication with the scan photo, unlisting, deletion and non-destructive republish. `testScanSavesPrivateItemAndShowsSellReview` passes the camera tab, disconnected Bluetooth panel, private save and prefilled listing review; it uses an explicitly marked UI-test fixture instead of real camera capture. The iPhone Release build passes. Physical-device camera, Bluetooth pairing/firmware decoding, Gemini and calibrated expiry forecasting have not been validated. Logs: `/tmp/gusto-scan-core.log`, `/tmp/gusto-scan-backend.log`, `/tmp/gusto-scan-ui.log`, `/tmp/gusto-scan-device.log`.
