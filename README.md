# Rescue — native iPhone demo

SwiftUI recreation of the Food Rescue Marketplace App Figma Make design. Runs on iOS 17+ with mock data, local photos, offline demo maps, native tabs/sheets, messaging, seller publishing, and a complete pickup/payment/impact flow. No backend, API keys, third-party packages, or permission prompts are required.

## Run in Simulator

1. Open `Rescue.xcodeproj` in Xcode 16.4 or later.
2. Select the **Rescue** scheme and an iPhone Simulator.
3. Run (⌘R). If a runtime is missing, install an iOS runtime in Xcode Settings → Components.
4. Tap Find food nearby on first launch. Subsequent launches start on Discover.

## Run on a physical iPhone

1. Connect the iPhone and select it as the run destination.
2. In target Rescue → Signing & Capabilities, select your development team. Automatic signing is enabled; use a unique bundle ID if Xcode asks.
3. Enable Developer Mode on the iPhone if required, trust your development certificate when prompted, and run.

Physical-device signing/install requires your Apple account and connected hardware. An unsigned device build validates compilation, not a signed installation. The app contains no Apple Pay, push, camera, or location entitlement to configure.

## Hackathon demo

1. Discover → Organic Strawberries → Reserve. Close the sheet.
2. Add Greek Yogurt from Buy again, then use Search for Sourdough Loaf and Rigatoni. Reserve both. The default 0.8mi distance filter includes all four. Filters next to Search combines budget, pickup time, freshness and preferences in one sheet.
3. Cart shows **4 items, 4 sellers, $7.75 to pay, $14.63 saved, 6.1 lb**. These figures come from the source fixtures.
4. Plan My Pickups → choose a route preference → Coordinate All.
5. Accept Nina's later pickup time (or Alternative). Downstream stop times update.
6. Start rescue run → tap the Next seller card → Simulate arrival → I'm Here → Looks good → Pay.
7. After Rescued, tap Next pickup. Repeat for the remaining sellers. At the last stop, tap See your impact.
8. Done enters You with updated impact. Purchases & Sales shows local demo receipts.

Payment buttons simulate payment and never charge money. Photos in pickup verification are clearly marked as reference photos. Report issue skips a seller without adding a receipt or impact. Reservations are held for the demo session; no real 30-minute server lock is claimed.

Other flows: Map price pins and carousel, search and filters, Fresh Check, editable chat and quick replies, mock photo scan → safety confirmation → local listing, saved items, impact charts, alerts, and native invitation sharing.

**Offline demo:** all 26 source photos are bundled. The default map recreates the Figma MapArt locally. You → Settings → Use live MapKit basemap enables Apple map tiles; coordinates remain fixed demo locations. Settings → Reset demo restores fixtures and clears demo activity.

## Tests and development

```sh
swift test
python3 Scripts/generate_project.py  # after adding/moving Swift files
xcrun swift-format format -i -r Sources Rescue Tests Package.swift Scripts/generate_icon.swift
./Scripts/test.sh                   # core + iPhone Simulator tests
```

Xcode: ⌘U runs unit and UI tests. See `docs/TESTING.md` for precise commands, coverage, screenshots, and environment requirements. The `--uitesting` launch argument skips onboarding and shortens mock delays without pre-filling the cart or bypassing the product flow.

## Documentation index

- `AGENTS.md`: concise file map and constraints; start here for targeted changes.
- `DESIGN.md`: source typography, tokens, patterns, states, native adaptations.
- `ARCHITECTURE.md`: ownership, invariants, lifecycle, mock boundaries, extension paths.
- `docs/TESTING.md`: test and build verification.
- `docs/ASSETS.json`: exact photo URLs and local asset availability.

This repository is intentionally left uncommitted. The user handles Git commits and pushes.
