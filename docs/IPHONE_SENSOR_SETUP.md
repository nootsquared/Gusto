# Run Gusto with the climate sensor on an iPhone

Use Xcode to install the development build directly. No App Store upload or IPA export is needed for your own phone. A free Apple Account can supply a Personal Team for development signing; its provisioning has limits and expires, requiring another install. A paid developer account is useful for TestFlight distribution, not necessary for this first device check.

1. Connect your unlocked iPhone to your Mac with a USB cable. Trust the computer on the phone if asked.
2. Open `Rescue.xcodeproj` in Xcode. The product is named Gusto on the phone; the internal target/scheme remains Rescue.
3. In Xcode → Settings → Accounts, add your Apple Account if needed.
4. Select the Rescue project → Rescue app target → Signing & Capabilities. Enable Automatically manage signing and choose your team. Keep `com.mhacks.rescue` and the existing `com.mhacks.rescue://oauth/callback` URL scheme. If Xcode reports that bundle ID is unavailable to your team, resolve signing before changing identifiers; the cloud authentication callback must remain registered.
5. Select your physical iPhone in the run-destination menu beside the Rescue scheme. If it is unavailable, open Window → Devices and Simulators to finish pairing/preparation. Your installed Xcode must support the iOS version on the phone.
6. On iPhone → Settings → Privacy & Security → Developer Mode, enable it and follow the restart/confirmation prompts. If the option is missing, first pair the phone with Xcode.
7. Press Run (⌘R). If the phone asks you to trust the developer, follow its prompt under Settings → General → VPN & Device Management.
8. Launch Gusto and sign in with Google as usual. Default app launches use Maincloud, not your Mac's localhost. If you previously configured a demo Xcode launch argument, remove `--fixture`, `--uitesting` and `--local-backend` from Product → Scheme → Edit Scheme → Run → Arguments for normal cloud use.

## Connect and view live readings

1. Power the Nano and FREE-WILi running the current repository firmware. Keep them nearby.
2. Disconnect LightBlue/nRF Connect or another phone that is already connected to the Nano. This firmware exposes a single central connection.
3. Hold the FREE-WILi **blue button for two seconds**. Wait for `BLE: PAIRING`. Advertising lasts up to 60 seconds.
4. Open Gusto → **Scan → Storage sensor → Find a device**. Allow Bluetooth access when iOS asks.
5. Select **MHacks Climate**. The app discovers the climate characteristic, reads the current sample and enables notifications. FREE-WILi should show `BLE: CONNECTED` and stop its pairing cue.
6. Watch the three Live conditions values update about once a second: **temperature °F** (with °C), **humidity % RH**, **light raw count**. Cover/uncover the sensor to check changing light. Light is not lux.
7. If packets stop for five seconds, the dashboard shows STALE and dashes. Invalid individual sensors also show dashes. If Bluetooth disconnects, hold blue again and repeat discovery.
8. Tap Disconnect to stop monitoring. Closing the panel leaves monitoring active. On an inventory item, tick **Track with sensor** to save valid readings privately about once a minute and show a provisional quality estimate after history arrives. Bluetooth background mode is enabled, but recording still depends on iOS delivering valid packets; disconnecting or force-quitting does not record readings. See `GEMINI_SCAN_SETUP.md` for the estimate's limits.

The standard iOS Simulator is for UI/decoder checks; this build intentionally requires a physical iPhone for actual BLE discovery. Your Mac builds and installs the app; the iPhone talks directly to the Nano. After installation, the Mac does not need to stay attached for the app to launch while its development provisioning remains valid.

## Verify on hardware

Confirm all three numbers match FREE-WILi within the devices' update timing. Test a missing sensor/cleared validity flag if available, power off the Nano to verify stale/disconnected values disappear, and reconnect to verify fresh readings resume. These checks require the actual phone and hardware and are not replaced by Simulator tests.

## Install for another tester

For a small in-person demo, repeat the USB/Xcode installation steps above for each phone. Use
the Xcode at `/Users/pranavmaringanti/Downloads/Xcode.app`, select **Rescue** and that person's
physical iPhone, keep automatic signing and the existing team, then press **Run**. Each person
must unlock their phone, trust the Mac, enable Developer Mode, and trust the developer under
Settings → General → VPN & Device Management if prompted. Pairing and signing can require
internet access. Disconnect after Gusto launches; normal app use talks directly to Maincloud.

Apple's free Personal Team permits up to three registered devices per platform and uses
seven-day provisioning. Reinstall when it expires. Xcode may refuse additional devices once
that limit is reached. For broader testing without connecting each phone to the Mac, use a paid
Apple Developer Program membership and TestFlight: create the app in App Store Connect,
archive the Rescue scheme for a generic iOS device, choose Distribute App → App Store Connect,
upload, then configure an external testing group. The first external build requires TestFlight
review. Send the resulting invitation/public link; testers install through TestFlight.

Each tester signs into Gusto with their own Google account. Choose the same browse area for a
demo: phone A scans, saves privately, then explicitly sells with pickup address/times; phone B
pulls to refresh Discover or searches for that food and messages the seller. A saved private scan
does not appear to other people until published. Gemini keys stay on the server. Nearby filters
still apply, so remote testers should select the listing's area. Internet is required for shared data.

Apple references: [Personal Team limits](https://developer.apple.com/support/compare-memberships/),
[external TestFlight testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

Apple documentation: [Run an app on a device](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html), [Signing & Capabilities](https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html), [Enable Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device/).
