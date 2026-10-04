import XCTest

#if canImport(RescueCore)
    @testable import RescueCore
#else
    @testable import Rescue
#endif

final class FoodInventoryTests: XCTestCase {
    func testSummaryRejectsOtherItemsDevicesFutureAndExpiredSamples() {
        let now = 1_000_000_000.0
        let item = InventoryFood(
            id: "tomato", name: "Tomato", scannedAt: now - 400_000, deviceID: "sensor")
        let readings = [
            StorageReading(
                itemID: "tomato", deviceID: "sensor", temperature: 20, humidity: 50, light: 100,
                recordedAt: now - 300_000),
            StorageReading(
                itemID: "tomato", deviceID: "sensor", temperature: 24, humidity: 70, light: 300,
                recordedAt: now - 100_000),
            StorageReading(
                itemID: "another", deviceID: "sensor", temperature: 70, humidity: 90, light: 900,
                recordedAt: now),
            StorageReading(
                itemID: "tomato", deviceID: "another", temperature: 70, humidity: 90, light: 900,
                recordedAt: now),
            StorageReading(
                itemID: "tomato", deviceID: "sensor", temperature: 70, humidity: 90, light: 900,
                recordedAt: now + 1),
            StorageReading(
                itemID: "tomato", deviceID: "sensor", temperature: 70, humidity: 90, light: 900,
                recordedAt: now - 500_000),
        ]
        let summary = StorageSummary.recent(readings, item: item, now: now)
        XCTAssertEqual(summary?.count, 2)
        XCTAssertEqual(summary?.temperature, 22)
        XCTAssertEqual(summary?.humidity, 60)
        XCTAssertEqual(summary?.light, 200)
        XCTAssertNil(StorageSummary.recent([], item: item, now: now))
    }
    @MainActor func testSavingFoodDoesNotPublishOrReserve() async {
        let store = AppStore(fixtureMode: true)
        let before = store.catalog.count
        let item = InventoryFood(name: "Tomato", variety: "Roma")
        let saved = await store.saveInventoryFood(item)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.inventory.first?.title, "Roma Tomato")
        XCTAssertFalse(store.inventory.first!.isListed)
        XCTAssertTrue(store.cart.isEmpty)
        XCTAssertNil(store.plan)
        XCTAssertEqual(store.catalog.count, before)
        var edited = item
        edited.quantity = "3 tomatoes"
        _ = await store.saveInventoryFood(edited)
        XCTAssertEqual(store.inventory.count, 1)
        XCTAssertEqual(store.inventory.first?.quantity, "3 tomatoes")
    }
    @MainActor func testListingUsesScannedPhotoAndUnlistingPreservesItem() async {
        let store = AppStore(fixtureMode: true)
        let item = InventoryFood(name: "Tomato", variety: "Roma", photoBase64: "example-photo")
        _ = await store.saveInventoryFood(item)
        let listed = await store.sellInventoryFood(
            item, price: 250, allergens: "None known",
            pickupAddress: "Ann Arbor", latitude: 42.28, longitude: -83.74,
            start: Date().addingTimeInterval(3600), end: Date().addingTimeInterval(7200),
            attestations: true)
        XCTAssertTrue(listed)
        let listingID = store.inventory.first!.listingID
        XCTAssertEqual(store.listing(listingID)?.name, "Roma Tomato")
        XCTAssertEqual(store.listing(listingID)?.imageURL, "data:image/jpeg;base64,example-photo")
        await store.unlistInventoryFood(item.id)
        XCTAssertNil(store.listing(listingID))
        XCTAssertEqual(store.inventory.first?.id, item.id)
        XCTAssertFalse(store.inventory.first!.isListed)
    }

}
