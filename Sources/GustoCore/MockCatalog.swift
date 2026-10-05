import Foundation

/// Exact product fixtures from the version 6 Figma export; money is integer cents.
public enum MockCatalog {
    public static let listings: [Listing] = [
        Listing(
            id: "straw", name: "Organic Strawberries", price: 250, retail: 649, distance: 0.3,
            freshness: .fresh, pickup: "Pickup tonight", updated: "2h ago", stale: false,
            sellerID: "maya", category: "Produce", quantity: "1 lb clamshell", weight: 1.0,
            opened: false, storage: "Refrigerated", allergens: "None", purchased: "Oct 2",
            receipt: true, vegetarian: true, prepared: false),
        Listing(
            id: "yog", name: "Unopened Greek Yogurt", price: 150, retail: 429, distance: 0.5,
            freshness: .good, pickup: "Until 9 PM", updated: "40m ago", stale: false,
            sellerID: "alex", category: "Dairy", quantity: "32 oz tub", weight: 2.0, opened: false,
            storage: "Refrigerated", allergens: "Milk", purchased: "Sep 30", receipt: true,
            vegetarian: true, prepared: false),
        Listing(
            id: "bread", name: "Sourdough Loaf", price: 200, retail: 700, distance: 0.6,
            freshness: .useSoon, pickup: "Before 7 PM", updated: "yesterday", stale: true,
            sellerID: "nina", category: "Bakery", quantity: "1 loaf", weight: 1.1, opened: false,
            storage: "Room temp", allergens: "Wheat", purchased: "Oct 3", receipt: false,
            vegetarian: true, prepared: false),
        Listing(
            id: "pasta", name: "Rigatoni, 2 boxes", price: 175, retail: 460, distance: 0.8,
            freshness: .fresh, pickup: "Pickup today", updated: "3h ago", stale: false,
            sellerID: "jordan", category: "Pantry", quantity: "2 × 16 oz", weight: 2.0,
            opened: false, storage: "Pantry", allergens: "Wheat", purchased: "Sep 12",
            receipt: true, vegetarian: true, prepared: false),
        Listing(
            id: "avo", name: "Hass Avocados", price: 225, retail: 599, distance: 0.4,
            freshness: .useSoon, pickup: "Available now", updated: "1h ago", stale: false,
            sellerID: "sam", category: "Produce", quantity: "4 ripe", weight: 1.4, opened: false,
            storage: "Room temp", allergens: "None", purchased: "Oct 1", receipt: false,
            vegetarian: true, prepared: false),
        Listing(
            id: "eggs", name: "Pasture Eggs", price: 200, retail: 549, distance: 0.7,
            freshness: .good, pickup: "Pickup tonight", updated: "5h ago", stale: false,
            sellerID: "alex", category: "Dairy", quantity: "10 of 12", weight: 1.3, opened: true,
            storage: "Refrigerated", allergens: "Egg", purchased: "Sep 28", receipt: true,
            vegetarian: true, prepared: false),
        Listing(
            id: "bana", name: "Ripe Bananas", price: 75, retail: 229, distance: 0.2,
            freshness: .useSoon, pickup: "Available now", updated: "20m ago", stale: false,
            sellerID: "maya", category: "Produce", quantity: "6 bananas", weight: 2.2,
            opened: false, storage: "Room temp", allergens: "None", purchased: "Sep 29",
            receipt: false, vegetarian: true, prepared: false),
        Listing(
            id: "gran", name: "Maple Granola", price: 300, retail: 899, distance: 1.1,
            freshness: .fresh, pickup: "Tomorrow AM", updated: "6h ago", stale: false,
            sellerID: "nina", category: "Breakfast", quantity: "12 oz, sealed", weight: 0.8,
            opened: false, storage: "Pantry", allergens: "Oats, almonds", purchased: "Sep 20",
            receipt: true, vegetarian: true, prepared: false),
        Listing(
            id: "spin", name: "Baby Spinach", price: 125, retail: 399, distance: 0.5,
            freshness: .good, pickup: "Pickup tonight", updated: "2h ago", stale: false,
            sellerID: "sam", category: "Produce", quantity: "5 oz", weight: 0.3, opened: false,
            storage: "Refrigerated", allergens: "None", purchased: "Oct 2", receipt: true,
            vegetarian: true, prepared: false),
        Listing(
            id: "milk", name: "Oat Milk, unopened", price: 150, retail: 449, distance: 0.9,
            freshness: .fresh, pickup: "Until 10 PM", updated: "1h ago", stale: false,
            sellerID: "jordan", category: "Dairy", quantity: "64 oz", weight: 4.2, opened: false,
            storage: "Refrigerated", allergens: "Oats", purchased: "Sep 30", receipt: true,
            vegetarian: true, prepared: false),
        Listing(
            id: "prep", name: "Homemade Pesto Pasta", price: 350, retail: 900, distance: 0.6,
            freshness: .fresh, pickup: "Tonight 6–8", updated: "30m ago", stale: false,
            sellerID: "nina", category: "Prepared", quantity: "2 servings", weight: 1.2,
            opened: true, storage: "Refrigerated · made 1 PM", allergens: "Wheat, pine nuts, milk",
            purchased: "Made today", receipt: false, vegetarian: true, prepared: true),
        Listing(
            id: "cereal", name: "Honey Oat Cereal", price: 199, retail: 529, distance: 1.0,
            freshness: .fresh, pickup: "Pickup today", updated: "4h ago", stale: false,
            sellerID: "jordan", category: "Breakfast", quantity: "14 oz, sealed", weight: 0.9,
            opened: false, storage: "Pantry", allergens: "Oats", purchased: "Sep 15", receipt: true,
            vegetarian: true, prepared: false),
        Listing(
            id: "chips", name: "Sea Salt Kettle Chips", price: 100, retail: 349, distance: 0.3,
            freshness: .fresh, pickup: "Available now", updated: "1h ago", stale: false,
            sellerID: "maya", category: "Snacks", quantity: "2 bags, sealed", weight: 0.5,
            opened: false, storage: "Pantry", allergens: "None", purchased: "Sep 25", receipt: true,
            vegetarian: true, prepared: false),
        Listing(
            id: "trail", name: "Trail Mix Packs", price: 200, retail: 699, distance: 0.4,
            freshness: .fresh, pickup: "Pickup today", updated: "2h ago", stale: false,
            sellerID: "alex", category: "Snacks", quantity: "6 packs", weight: 0.8, opened: false,
            storage: "Pantry", allergens: "Peanuts, almonds", purchased: "Sep 18", receipt: true,
            vegetarian: true, prepared: false),
        Listing(
            id: "hummus", name: "Hummus & Pita Chips", price: 175, retail: 499, distance: 0.5,
            freshness: .good, pickup: "Until 9 PM", updated: "1h ago", stale: false,
            sellerID: "sam", category: "Snacks", quantity: "10 oz, unopened", weight: 0.7,
            opened: false, storage: "Refrigerated", allergens: "Sesame, wheat", purchased: "Oct 1",
            receipt: true, vegetarian: true, prepared: false),
        Listing(
            id: "bars", name: "Oat Protein Bars", price: 250, retail: 749, distance: 0.6,
            freshness: .fresh, pickup: "Pickup tonight", updated: "3h ago", stale: false,
            sellerID: "jordan", category: "Snacks", quantity: "5 bars", weight: 0.6, opened: false,
            storage: "Pantry", allergens: "Oats, milk", purchased: "Sep 20", receipt: true,
            vegetarian: true, prepared: false),
        Listing(
            id: "curry", name: "Chickpea Coconut Curry", price: 400, retail: 1100, distance: 0.4,
            freshness: .fresh, pickup: "Tonight 6–8", updated: "25m ago", stale: false,
            sellerID: "maya", category: "Prepared", quantity: "2 servings", weight: 1.4,
            opened: true, storage: "Refrigerated · made 2 PM", allergens: "Coconut",
            purchased: "Made today", receipt: false, vegetarian: true, prepared: true),
        Listing(
            id: "bowl", name: "Burrito Bowl", price: 350, retail: 1050, distance: 0.7,
            freshness: .fresh, pickup: "Until 8 PM", updated: "40m ago", stale: false,
            sellerID: "alex", category: "Prepared", quantity: "1 large bowl", weight: 1.0,
            opened: false, storage: "Refrigerated · sealed", allergens: "Milk",
            purchased: "Bought today", receipt: true, vegetarian: true, prepared: false),
        Listing(
            id: "soup", name: "Tomato Basil Soup", price: 250, retail: 650, distance: 0.5,
            freshness: .good, pickup: "Pickup tonight", updated: "1h ago", stale: false,
            sellerID: "sam", category: "Prepared", quantity: "1 qt", weight: 2.1, opened: false,
            storage: "Refrigerated · made 11 AM", allergens: "Milk", purchased: "Made today",
            receipt: false, vegetarian: true, prepared: true),
        Listing(
            id: "salad", name: "Grain & Greens Salad", price: 300, retail: 925, distance: 0.9,
            freshness: .useSoon, pickup: "Before 7 PM", updated: "2h ago", stale: false,
            sellerID: "jordan", category: "Prepared", quantity: "1 bowl, sealed", weight: 0.8,
            opened: false, storage: "Refrigerated", allergens: "Sesame", purchased: "Bought today",
            receipt: true, vegetarian: true, prepared: false),
    ]
    public static let sellers: [Seller] = [
        Seller(
            id: "maya", name: "Maya R.", rating: 4.9, pickups: 37, responds: "~5 min",
            student: true, area: "Elm & 4th", latitude: 42.279, longitude: -83.744),
        Seller(
            id: "alex", name: "Alex P.", rating: 5.0, pickups: 22, responds: "~3 min",
            student: false, area: "Linden Park", latitude: 42.2812, longitude: -83.738),
        Seller(
            id: "nina", name: "Nina C.", rating: 4.8, pickups: 54, responds: "~8 min",
            student: true, area: "North Campus", latitude: 42.278, longitude: -83.735),
        Seller(
            id: "jordan", name: "Jordan K.", rating: 4.9, pickups: 18, responds: "~10 min",
            student: false, area: "Mill District", latitude: 42.2748, longitude: -83.7395),
        Seller(
            id: "sam", name: "Sam W.", rating: 4.7, pickups: 9, responds: "~15 min", student: false,
            area: "Harbor St", latitude: 42.2763, longitude: -83.747),
    ]
}
