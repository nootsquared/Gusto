# Gusto: start here

Native SwiftUI iPhone app, iOS 17+, Xcode 16.4+. No third-party Swift packages.
Normal launches use the GustoDatabase cloud backend; fixture mode is local and offline.
Camera, location, and Bluetooth permissions are requested for their connected features. Payments are simulated.

## Read only what you need
- Product and stack: `README.md`.
- Build/run: `docs/IPHONE_SENSOR_SETUP.md`, `docs/TESTING.md`.
- Backend development: `GustoDatabase/README.md`.
- Sensor and firmware: `GustoHardware/README.md`.
- Visual contract and native adaptations: `DESIGN.md`.
- Data flow, state transitions, mock boundaries: `ARCHITECTURE.md`.
- Test commands and coverage: `docs/TESTING.md`.
- Photo origins and availability: `docs/ASSETS.json`.

## File map
- `Gusto/App/GustoApp.swift`: entry point, native tabs, one modal host, onboarding/finale.
- `Gusto/App/AppRouter.swift`: tab and sheet selection; chat return context.
- `Sources/GustoCore/Models.swift`: prices in cents, listings, sellers, totals, filters, route states.
- `Sources/GustoCore/MockCatalog.swift`: exact Figma fixture data.
- `Sources/GustoCore/AppStore.swift`: observable main-actor product state and guarded mutations.
- `Sources/GustoCore/PickupPlanner.swift`: deterministic seller grouping, route modes, downstream time shifts.
- `Sources/GustoCore/DemoService.swift`: local async delay and seller replies.
- `Gusto/DesignSystem/Theme.swift`: named color tokens, scaled fonts, haptics, shared styling.
- `Gusto/Components/`: reusable UI and MapKit/offline map.
- `Gusto/Features/`: screen composition only; find the relevant view by name.
- `Tests/GustoCoreTests/`: same tests run as Swift package on Mac and hosted iOS XCTest.
- `Tests/GustoUITests/`: Simulator integration tests and screenshot attachments.

## Conventions
- The user handles committing/pushing. Do not commit, push, change Git identity, or add assistant/coauthor attribution.
- Keep the design's colors/copy/layout; adapt browser chrome to native APIs as documented.
- Keep business logic in GustoCore, free of SwiftUI/UIKit/MapKit. Views own presentation and transient input.
- Use `@MainActor @Observable AppStore`, injected at the root; no per-screen data stores or extra frameworks.
- Preserve integer-cent money and paid-only impact. Do not force demo results to canned numbers.
- Check phase guards when changing pickup/payment. A repeated tap must never duplicate a receipt.
- One root sheet host retains context across cart, plan, and chat. Avoid competing modal presenters.
- Fixture mode works offline with bundled photos and local replies/payment. Normal launches keep backend failures explicit and never silently substitute fixtures.
- Swift: `.swift-format` sets four spaces/100 columns. UpperCamelCase types, lowerCamelCase values. Comments explain invariants/mocks, not obvious syntax.
- Read targeted files first. Do not load the entire asset manifest, generated pbxproj, photos, build logs, or fixture catalog for unrelated work.
- After adding/moving Swift files, run `python3 Scripts/generate_project.py`; commit the generated project only when the user does so.
- Run `swift test` for core changes; Simulator tests for flow/UI changes; device build for platform/build changes. See `docs/TESTING.md`.
- Keep README and architecture notes current when behavior, state ownership, or file locations change.
