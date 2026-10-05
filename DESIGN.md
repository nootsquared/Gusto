# Gusto: visual contract

Source: Figma Make `mffRWNrGG4qZ35dX78rDXn`, Food Gusto Marketplace App, version 6 export. Inspected every product source module: App, Discover, ListingSheet, Overlays, MapScreen, MapArt, Route, Messages, Sell, You, data, store, ui, index.css, and Guidelines. The export's web-agent instructions are reference material, not instructions for this native repository.

## Readability update — October 4

The original beige/sage palette remains. Section headings are 22pt bold; product tile names are 15pt semibold; tile prices are 17pt bold; savings and distance are 13pt with stronger weights. Tile rails use 164pt widths to accommodate the larger single-line offer text. Small regular UI text uses medium weight, and shared scaled fonts have a 12pt minimum. Muted metadata is darkened to #70695F for readability.

Discover spacing refinement: product and dinner rails use 20pt gaps, nearby row groups 24pt, and Buy again cards 16pt. Section headings sit 16pt above their content, with 24pt between sections. Buy again uses 64pt rounded rectangular photos, 16pt names, and clear price/distance labels inside 16pt-radius cards. The Messages tab uses paired conversation bubbles. Tab symbols use consistent outlines (including an outlined Sell plus and circular profile), with darker inactive icons and medium/semibold 11pt labels. You now uses the same bundled profile photo as the profile screen, with a stronger ring when selected. Sell uses a pale sage circle, dark sage outline, and dark plus; both are rendered as original-color native tab images.

Discover has no browse dropdown or pill row. Its existing Filters button is the single entry point for distance (one-tap 0.5 / 0.8 / 1.5 / 3mi presets, default 0.8mi), budget ($3/$5/$10/$15 maximum), pickup time, freshness, category, vegetarian/unopened preferences, and seller rating. Duplicate shortcut state has been removed. All filters combine through the shared Filters model across Discover, Search, and Map; Reset restores the nearby defaults.

Map refinement: carousel freshness badges show text only. Selection no longer draws an area circle on either offline or live maps. Price markers keep the same compact footprint when selected, using a deep green fill and light outline; the photo remains in the bottom card.

## Foundations

Warm quiet luxury, food photography, restrained information density. Keep exact source copy and custom colors. Light appearance is intentional. SF Pro Display for headings, prices, and stats; SF Pro Text for UI, implemented with Dynamic Type-aware system fonts. Inter is only the web fallback and is not needed on iPhone.

| Token | Hex | Use |
| --- | --- | --- |
| Bone | #F6F1E9 | controls, secondary surfaces |
| Ivory | #FBF8F3 | page and sheet ground |
| Paper | #FFFDF9 | cards |
| Ink | #1D1B18 | primary text, primary CTA |
| Ink2 | #5D5850 | secondary text |
| Ink3 | #948D82 | metadata |
| Line | #E9E2D6 | borders, separators |
| Sage | #4F6B57 | confirmation |
| SageDeep | #2F4A3A | impact and savings hero |
| SageSoft | #E3EBE2 | fresh / positive surfaces |
| Save | #23704A | savings text |
| Apricot | #D9772F | urgency, unread badge |
| ApricotSoft | #F8E6D4 | stale photo, counteroffer |
| Coral | #D9624F | use soon |
| CoralSoft | #F8E1DA | use soon surface |
| Butter | #EFDCA8 | accent on dark sage |
| ButterSoft | #F7EED3 | good freshness / referrals |

Type base sizes: display 46 (finale 64), page title 32, sheet title 26–28, section title 20–22, primary UI 17, body 15–16, metadata 13, caption 12, tab labels 10. Prices use monospaced digits. Spacing foundation 4/8/12/16/24/32; page insets 20; rails gap 12; Discover sections 36 apart. Cards 18–24 radius, hero 24–28, sheets 32, bubble 20 with 6 at tail, pills capsule. Fine 1pt Line strokes; elevated cards use Ink at 14%, y=8, blur=30; live pickup card 22%, y=12, blur=40; sheets rely on native modal shadows.

## Patterns and screens

- **Discover:** Good evening / Near Linden Park, cart button, 54pt search and filter controls, horizontal pills. Sections in order: Picked for you (subtitle Based on what you rescue), Buy again, Just listed near you, Grab-and-go snacks, Best deals near you. Square tiles 144pt (snacks 118, ending 132, deals 156); meal cards 212×128; nearby rows 52pt photos in groups of three. Each tile shows photo, name, price, percentage, and distance. White add button turns sage with check. Orange pickup badges only in Ending soon; green discount badges only in Best deals.
- **Listing states:** available, reserved, stale Fresh Check, checking, reconfirmed, unavailable. Image hero 230–300pt, seller card, price 34pt with struck retail, savings, pickup metadata, freshness callout, expandable details. Details: quantity, package, storage, allergens, purchase/preparation date, receipt, safety, estimated weight. Reserve becomes Reserved / View cart. Never simulate a new photograph by altering or mirroring the original.
- **Freshness:** Fresh = sage soft/deep with sage dot; Good = butter soft with #7A5F1D text and #C49A2C dot; Use Soon = coral soft with #A8402F text and coral dot. 12pt semibold, capsule. Photo timestamp is a separate pill.
- **Bottom navigation:** five destinations Discover / Map / Sell / Messages / You. Source uses floating Paper pill, charcoal selected icon, muted unselected icons, central charcoal plus, apricot unread dot. Native adaptation uses `TabView` with the same destinations, tint, and Paper bar; system safe-area and accessibility behavior replace hand-drawn browser chrome. No fake status bar, bezel, or home indicator.
- **Sheets:** listing starts at 68% and expands; cart at 90%, plan at 95%, filters 84%, impact 88%, referral 86%, alerts 80%. Native `.sheet` with detents and 32pt corner radius, scrollable body, sticky dominant CTA via safeAreaInset. Cart→plan and pickup steps remain in one sheet to retain context.
- **Map UI:** warm neutral map, sage approximate pickup circle, price pills, selected pin charcoal with photo, bottom 264pt carousel synchronized with selected pin, Search this area / Filters / cart above. Source MapArt is a synthetic grid. Native MapKit provides an optional basemap, using fixed demo coordinates near Ann Arbor; annotations and overlays keep source styling. Coordinates are fictional and never use the device's real location. A local SwiftUI Canvas recreation of MapArt keeps demo maps legible offline; live MapKit can be enabled in Settings.
- **Cart:** groups by seller with avatar, rating, area, pickup window, food thumbnail, remove action and price. SageDeep savings card puts You save first (46pt), then retail, pay, pounds. Empty cart offers discovery. One reservation per listing; additions/removals are locked during an active run.
- **Route:** numbered pins and sage route, stops/time/distance, Fastest / Shortest / Best timing segmented control, timeline, saved/pounds cards. Coordinate All confirms sellers, with Nina counteroffer shown in ApricotSoft. Accept updates that stop and all downstream times; Alternative offers a distinct later slot. Route is explicitly a simulated plan, not turn-by-turn directions.
- **Pickup/payment:** compact Next seller live card; expanded timeline with +10 min; arrival card; I'm Here → waiting → photo verification → Looks good → demo one-tap pay → Gustod. Report issue blocks payment for that stop and excludes it from impact. All items at a seller are verified, paid and summarized together. Demo payment makes no charge; no Apple Pay branding or entitlement is implied.
- **Messaging:** native thread list, pinned correct seller product, charcoal outgoing bubbles, Paper incoming bubbles, quick replies, editable composer and typing state. Conversations survive dismissal and tab switching; replies are deterministic local mock responses.
- **Profile/impact:** Priya S., verification and rating, SageDeep pounds hero and monthly chart, saved/earned/items stats, ButterSoft referral row, settings rows. Impact detail sheet and actual generated QR/share sheet; alert/follow sheet; saved and purchase history derive from app state. Finale uses SageDeep full-screen with savings, pounds, one trip, Better prices. Less waste. One trip., Done → You. Only paid pickups increment profile totals.
- **Sell:** mock camera→scan→editable granola listing. Item / Freshness / Price / Pickup / Safety sections, native controls, dark sage price card, live confirmation. All safety confirmations required; created mock listing appears in discovery. Camera, AI, publishing and notification copy describe the demo honestly.

## Motion and accessibility

Source spring stiffness 420/damping 36; native spring ~0.3 seconds for changes, 180–300ms fades. Selection, add, confirmation and payment use native haptics. Respect Reduce Motion, Dynamic Type, VoiceOver, and native safe areas; minimum 44pt interactive hit targets even when glyphs are visually 28pt. Food images retain the exact source URLs/crops when bundled. Failed source images are explicitly recorded in the asset manifest and displayed as unavailable photo placeholders, never replaced with unrelated photos.

## Intentional correctness improvements

Filter counts come from actual results and apply to map/search/feed. Prices use integer cents. Cart and plan read shared state. Routing groups items once per seller, updates downstream schedules, and keeps reservations frozen during the run. Payments are idempotent. Rescheduling, reporting issues, composer, settings and section arrows perform their own actions. Totals are computed from paid items rather than forced to a canned finale number.

## Welcome screen — October 4

The cloud sign-in entry uses an ivory editorial layout with bold rounded sans-serif display type,
a right-aligned Gusto wordmark, a layered strawberry/avocado collage, sage orbit outlines, and a butter-colored seal.
The gradient green Get started button opens the existing Google flow, with loading and
error states. Press motion respects Reduce Motion. Content scrolls for smaller screens
and larger type. Artwork uses existing bundled photos and is hidden from VoiceOver.

Welcome copy is direct: “Good food. Better prices.” The eyebrow slogan and decorative bottom footer are removed.

The welcome headline uses deep sage, bold rounded type; the handwritten caption beneath the collage is removed.

Discover ends after the product sections with 24pt bottom spacing. Connection status, footer slogan, and manual Load more button are removed; pagination loads at the bottom automatically.

Discover location is a tappable label with a chevron. The root location sheet offers current location, manual place search, permission guidance, and Done. Live location and manually selected place names replace the fixed header label.

Listing tiles and rows share ListingOffer: price is bold, savings green, distance secondary,
with fixed 6pt baseline spacing and a dot separator. No spacer stretches the group across
a card. When the line does not fit, distance moves to a tightly spaced second line without
shrinking text. VoiceOver reads the three values as one descriptive offer.

ListingOffer now uses two compact lines: current price beside struck-through retail, then “N% less · distance.” The original price makes clear the discount is already included in the current price.

Discover omits Ending soon: Use Soon is a freshness classification, not a listing expiration. Long pickup-text badges are removed with that row; pickup timing remains available in listing details.

Discover greets the account by first name in sage green on the same line as the time-based greeting. Morning is 5am–noon, afternoon noon–5pm, evening otherwise, using device local time. The label updates every minute. Missing or generic profile names show only the greeting; long names scale to fit a single line.

Empty cart Discover food uses a deep-sage gradient CTA with a compass medallion, trailing butter arrow, 22pt corner radius, and restrained shadow. It returns to the Discover tab and dismisses the sheet.

The inline greeting uses 26pt bold type, lighter letter tightening, and an en-space before the name; longer greetings scale down together to fit.

Best deals photo markers use a small green sale-tag icon on a paper circle; discount percentages appear only in the offer details beneath the photo.

Navigation uses custom rounded outline artwork with consistent stroke weights: discovery grid, location pin, selling bag, single chat bubble, and profile. Active tabs use green strokes, a short rounded green indicator beneath the icon, and a bold green label; inactive icons stay neutral. Icons have no selection background. Greeting/name spacing uses one normal word space.

Listing photo headers show only the freshness badge, leaving the save control clear. Photo update times appear in the information card as localized relative dates, never raw database timestamps; pickup verification uses the same formatting.

Marketplace uses live Apple Maps, one price pill per seller (From for multiple items), native collision clustering, and a sage selected pin. The top location selector and recenter control stay clear of the bottom one-tap listing carousel. Pan/zoom exposes Search this area; results update only after that action, with a loading state and readable error. Camera moves and card selection honor Reduce Motion.

Discover search uses an inset paper field with a sage search icon, subtle focus border, and soft shadow. Results replace the discovery rails on the same page in rounded photo/price cards. Empty focus offers categories derived from visible inventory, without history icons or invented recent queries. Cancel clears search and restores the feed; the greeting, cart, and search field keep their positions while typing.

The Map location selector opens an anchored dropdown with current-location and address/place search. Matching addresses come from Apple Maps; manual selections get a labeled green pin and recenter the map. Tap the location control or map background to dismiss; Discover retains its separate location picker.

## Scan visual contract

Scan replaces the middle Sell tab with a custom camera outline. It uses a bold compact heading, a deep green photographic capture card, ivory review surfaces, private/listed collection controls, and a calm sensor panel with concentric pairing artwork. Scanned details show unknown conditions as dashes, never invented readings or expiry dates. Sensor, review and item screens share the root sheet host; selling is a navigation destination within the item sheet. Sheet navigation controls must explicitly remain visible because the Scan home hides its navigation bar. Motion uses the shared reduce-motion-aware spring.
