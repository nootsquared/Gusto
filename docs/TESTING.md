The final signed iPhone build passed (`/tmp/gusto-notifications-build.log`). Filtered Snacks
and inline search gallery tests passed (`/tmp/gusto-gallery-ui.log`); clearing filters restored
recommendations. The filtered gallery screenshot was visually inspected after export to
`/tmp/gusto-gallery-attachments`. Following the deployment command, Maincloud was updated without deleting data and the app was installed on Noot Noot (iPhone 17 Pro). Automatic launch was blocked because the phone was locked. Logs: `/tmp/gusto-notifications-cloud-deploy.log`, `/tmp/gusto-notifications-phone-install.log`, `/tmp/gusto-notifications-phone-launch.log`.

October 4 notifications/cart/inventory follow-up: 51 core tests passed with one opt-in skip.
The isolated backend suite passed inbox summaries, unread counts and mark-read updates,
Fresh Check replies once across retries, real-account cart previews, known original-price/weight
values, exact pickup coordinates, reservation-blocked unlisting, removal and persistence after
republishing. Publication now works without a safety checklist or fabricated attestation rows.
Simulator tests passed cart/pickup, scan/sell keyboard and live-address selection, and the
revised selling screen without a checklist. Logs: `/tmp/gusto-notifications-core.log`,
`/tmp/gusto-notifications-backend.log`, `/tmp/gusto-notifications-ui.log`,
`/tmp/gusto-notifications-sell-ui.log`. Foreground notification logic was checked through core
and backend tests; physical two-phone notification delivery and GPS accuracy await device use.
Deployment and installation are complete; launch and physical two-phone verification require unlocking the device.

# Testing and verification

October 4 final account/location/listing fixes: 49 core tests passed with one opt-in skip.
The isolated backend integration passed exact published coordinates, real storage snapshots,
own-listing exclusion, rejected self-purchase, and a Fresh Check message delivered to the seller
exactly once across repeated requests. Schema republish preserved account/inventory/receipt data.
The focused scan/save/sell Simulator test passed price entry, keyboard Done, and live address
selection. The final signed build was installed and launched on the connected iPhone; the cloud
module was deployed with `--delete-data=never`, and storage backfill completed.
Logs: `/tmp/gusto-final-fixes-core.log`, `/tmp/gusto-final-fixes-backend-final.log`,
`/tmp/gusto-final-fixes-ui.log`, `/tmp/gusto-final-fixes-phone.log`,
`/tmp/gusto-final-fixes-cloud.log`, `/tmp/gusto-final-fixes-install.log`,
`/tmp/gusto-final-fixes-launch.log`. Physical GPS accuracy and long-running provider token renewal
still require normal device use; they were not simulated by changing the user's credentials.

October 4 pickup-location follow-up: the focused scan/save/sell Simulator test passed live address
typing and selecting the first MapKit match without a Find address button. The signed iPhone build
passed. Logs: `/tmp/gusto-pickup-location-ui-final.log`, `/tmp/gusto-pickup-location-phone.log`.
Startup now sends an expired, unrefreshable stored session to Welcome and retains the account
for transient failures; this branch was inspected and compiled, not forced by expiring the
user's actual credentials.

## Gemini scanning and sensor history — October 4, 2026

Initial verification was local. Following the user's deployment command, the shared Maincloud
backend was updated without deleting data, Gemini configured, and search indexes rebuilt.
The cloud retained 200 listing records. The signed Debug build was installed and launched normally
on the connected iPhone 17 Pro. Logs: `/tmp/gusto-gemini-cloud-deploy.log`,
`/tmp/gusto-gemini-phone-build.log`, `/tmp/gusto-gemini-phone-install.log`,
`/tmp/gusto-gemini-phone-launch.log`. This confirms installation and launch, not a completed physical
two-account or sensor test. The replacement Gemini key successfully analyzed a real banana
photo, returning ripe condition and a crop box. Reusing that recorded analysis, the isolated
two-account smoke check passed private save, owner-only tracking, raw BLE history, explicit
publication, singular-name search, listing photo access and seller chat. No second paid analysis
was needed for the search regression.

The core suite passed 49 tests with one opt-in test skipped and no failures. Coverage includes
quality estimates requiring matching food metadata and valid device history, warmer conditions,
unlinking, and invalidated suggestions after edits. The final backend suite passed authentication,
inventory ownership, marketplace/pickup transitions and persistence through non-destructive
republishing. Simulator tests passed inline Discover search and private scan/save/sell review;
the scan flow uses an explicitly marked fixture. The unsigned iPhone Release build passed.

Logs: `/tmp/gusto-gemini-core.log`, `/tmp/gusto-gemini-backend-final.log`,
`/tmp/gusto-gemini-live-smoke.log`, `/tmp/gusto-gemini-ui-final.log`,
`/tmp/gusto-gemini-device.log`. Physical BLE recording, real Google avatar presentation, and
two physical phones remain unverified. Quality estimates are provisional and uncalibrated;
these tests do not establish a food-safety expiration model. See `GEMINI_SCAN_SETUP.md` for setup.

## Cloud browsing and foreground sync

The 2026-10-04 core run passes 45 tests with one live-backend opt-in skipped. Coverage includes
later-page additions, withdrawn listings, interrupted refresh preserving the previous snapshot,
and wider-area suggestions respecting other filters. The isolated database suite passes private
scan ownership, publication visible to another account, and persistence after republish. Read-only
Maincloud checks found 197 published listings; no cloud users or inventory were modified for testing.

Simulator checks pass Discover empty-area controls, map results outside a narrower Discover radius,
the location panel's single Done button, and the sensor dashboard/physical-device requirement.
The final unsigned iPhone Release build passes with Xcode 26.3. A two-physical-phone scan/publish
check remains: sign in normally on each phone, save a scan, explicitly publish it, then check
Discover/Map from the second account in the same area after a refresh. Foreground polling is about
ten seconds. Logs: `/tmp/gusto-feed-core.log`, `/tmp/gusto-sync-backend.log`,
`/tmp/gusto-feed-ui-final.log`, `/tmp/gusto-feed-ui-latest.log`, `/tmp/gusto-feed-device-final.log`.

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

## Nano BLE live dashboard — October 4, 2026

The core suite passed 43 tests (1 existing opt-in live-backend test skipped), including four
climate-protocol tests covering the exact byte layout, signed Fahrenheit/Celsius conversion,
validity masks, malformed/out-of-range packets, raw light counts, duplicate read/notify records,
sequence/uptime wrapping, reconnect resets and the five-second stale deadline.

Simulator checks `testSensorDashboardAndPhysicalDeviceRequirement` and
`testScanSavesPrivateItemAndShowsSellReview` passed. The dashboard test checks three empty values
before hardware is connected and the explicit physical-iPhone requirement instead of fake BLE
readings. The final layout/state adjustment passed the dashboard check again. Unsigned Release
builds for generic iOS passed; this verifies compilation, not development signing or installation.
Logs: `/tmp/gusto-ble-core.log`, `/tmp/gusto-ble-ui.log`, `/tmp/gusto-ble-ui-final.log`,
`/tmp/gusto-ble-device-final.log`.

The actual Gusto-to-Nano radio path still requires a physical iPhone test using
[IPHONE_SENSOR_SETUP.md](IPHONE_SENSOR_SETUP.md). Existing firmware/LightBlue verification
in `Developer/BLE_PROTOCOL.md` does not substitute for testing this new app adapter.

October 4 pickup/discovery fixes: 48 core tests passed (one opt-in backend test skipped),
backend typecheck and isolated-server integration passed. The integration exercises selected-origin
planning, stop reordering, seller confirmation, handoff, duplicate request protection and scan
publication. Four Simulator UI checks passed for pickup flow, inline search, address selection and
scan/sell review. The final repeated zoom/search regression passed after switching map searches to
full canvas bounds; attribution layout margins must not narrow the searched area. Final signed
iPhone build passed using Xcode 26.3. Logs: `/tmp/gusto-fixes-core.log`,
`/tmp/gusto-fixes-backend.log`, `/tmp/gusto-fixes-ui.log`, `/tmp/gusto-map-final.log`,
`/tmp/gusto-fixes-phone-build-final.log`. Cloud module publishing succeeded with
`--delete-data=never`; a read-only post-deployment query confirmed 197 published listings.
These tests do not verify real payment processing, a physical seller-to-buyer exchange or the
Google provider's account photo on the user's phone.

## Pickup completion and scan naming — October 4, 2026

The core suite passed 52 tests with one opt-in skip. The isolated backend suite passed confirmed
pickup removal from the shopping cart, retained trip details, seller confirmation and buyer arrival
messages, rejection of early/wrong-account demo payments, successful buyer demo payment with local
simulation disabled, and a single receipt across retries. Non-destructive republish preserved data.
The full four-seller Simulator pickup test passed arrival, handoff review, demo payment and trip
summary. The focused scan review test passed labeled menus; backend checks passed normalized banana
names and exact published GPS coordinates with a dropped-pin label. Physical GPS acquisition and
two-phone pickup notifications remain unverified. The latest backend was deployed without deleting data, and the signed build was installed and
launched on the connected iPhone 17 Pro. Installation and launch do not establish a completed
two-phone pickup test.
Logs: `/tmp/gusto-pickup-completion-core.log`, `/tmp/gusto-pickup-completion-backend.log`,
`/tmp/gusto-pickup-completion-ui.log`, `/tmp/gusto-pickup-completion-device.log`,
`/tmp/gusto-scan-pin-ui.log`.

Pickup deployment logs: `/tmp/gusto-pickup-completion-cloud-deploy.log`,
`/tmp/gusto-pickup-completion-phone-install.log`, `/tmp/gusto-pickup-completion-phone-launch.log`.

Discover pickup-card placement: removed the root bottom inset and inserted the trip card below
search in the feed. Signed iPhone build and installation passed. This layout-only follow-up did
not repeat the pickup transaction tests. Logs: `/tmp/gusto-pickup-card-placement-build.log`,
`/tmp/gusto-pickup-card-placement-install.log`, `/tmp/gusto-pickup-card-placement-launch.log`.

Pickup cancellation: 53 core tests passed with one opt-in skip; isolated backend checks passed
owner-only cancellation, released claims, removed cart entries, seller messaging and retries.
Signed iPhone build passed; cloud deployed without deleting data and updated app installed.
Logs: `/tmp/gusto-pickup-cancel-core.log`, `/tmp/gusto-pickup-cancel-backend.log`,
`/tmp/gusto-pickup-cancel-build.log`, `/tmp/gusto-pickup-cancel-cloud.log`,
`/tmp/gusto-pickup-cancel-install.log`, `/tmp/gusto-pickup-cancel-launch.log`.
