import { schema, table, t } from 'spacetimedb/server';

// All base tables are deliberately private. Only authenticated procedures expose projections.
const users = table({ name: 'users' }, {
  id: t.string().primaryKey(), name: t.string(), avatar: t.string(), status: t.string(), created: t.u64(),
});
const userIdentities = table({ name: 'user_identities' }, {
  identity: t.identity().primaryKey(), userId: t.string().index('btree'),
});
const userPreferences = table({ name: 'user_preferences' }, {
  userId: t.string().primaryKey(), vegetarian: t.bool(), area: t.string(), smartAlerts: t.bool(), version: t.u32(),
});
const listings = table({ name: 'listings', indexes: [
  { accessor: 'bySeller', algorithm: 'btree', columns: ['sellerId', 'status'] },
  { accessor: 'byPublished', algorithm: 'btree', columns: ['status', 'creationOrder', 'id'] },
  { accessor: 'byArea', algorithm: 'btree', columns: ['area', 'status', 'creationOrder', 'id'] },
]}, {
  id: t.string().primaryKey(), sellerId: t.string(), title: t.string(), description: t.string(),
  category: t.string(), quantity: t.string(), price: t.u32(), retail: t.u32(), grams: t.u32(),
  freshness: t.string(), opened: t.bool(), prepared: t.bool(), storage: t.string(), allergens: t.string(),
  vegetarian: t.bool(), purchased: t.string(), bestBy: t.string(), status: t.string(), area: t.string(),
  version: t.u32(), created: t.u64(), creationOrder: t.u64(), updated: t.u64(),
});
const mediaAssets = table({ name: 'media_assets' }, {
  id: t.string().primaryKey(), ownerId: t.string().index('btree'), key: t.string(), hash: t.string(),
  mime: t.string(), width: t.u32(), height: t.u32(), visibility: t.string(), state: t.string(), created: t.u64(),
});
const listingMedia = table({ name: 'listing_media' }, {
  id: t.string().primaryKey(), listingId: t.string().index('btree'), mediaId: t.string(), role: t.string(), order: t.u32(),
});
const pickupLocations = table({ name: 'pickup_locations' }, {
  id: t.string().primaryKey(), sellerId: t.string().index('btree'), area: t.string(),
  latitude: t.f64(), longitude: t.f64(), exactLatitude: t.f64(), exactLongitude: t.f64(),
  address: t.string(), instructions: t.string(),
});
const listingPickupWindows = table({ name: 'listing_pickup_windows' }, {
  id: t.string().primaryKey(), listingId: t.string().index('btree'), locationId: t.string(),
  start: t.u64(), end: t.u64(), timezone: t.string(),
});
const listingAttestations = table({ name: 'listing_attestations' }, {
  id: t.string().primaryKey(), listingId: t.string().index('btree'), version: t.u32(), sellerId: t.string(),
  safeStorage: t.bool(), accurateCondition: t.bool(), noSpoilage: t.bool(), allergensDeclared: t.bool(), confirmed: t.u64(),
});
const tags = table({ name: 'tags' }, { id: t.string().primaryKey(), label: t.string(), kind: t.string() });
const listingTags = table({ name: 'listing_tags' }, {
  id: t.string().primaryKey(), listingId: t.string().index('btree'), tagId: t.string(),
});
const listingSearchTerms = table({ name: 'listing_search_terms', indexes: [
  { accessor: 'byGlobalTerm', algorithm: 'btree', columns: ['token', 'creationOrder', 'listingId'] },
  { accessor: 'byTerm', algorithm: 'btree', columns: ['area', 'token', 'creationOrder', 'listingId'] },
]}, { id: t.string().primaryKey(), listingId: t.string().index('btree'), area: t.string(), token: t.string(), created: t.u64(), creationOrder: t.u64() });
const searchTermStats = table({ name: 'search_term_stats' }, {
  id: t.string().primaryKey(), count: t.u32(),
});
const carts = table({ name: 'carts' }, { userId: t.string().primaryKey(), version: t.u32(), updated: t.u64() });
const cartItems = table({ name: 'cart_items' }, {
  id: t.string().primaryKey(), buyerId: t.string().index('btree'), listingId: t.string(), reservationId: t.string(), added: t.f64(),
});
const reservations = table({ name: 'reservations', indexes: [
  { accessor: 'byBuyer', algorithm: 'btree', columns: ['buyerId', 'status', 'expires'] },
]}, {
  id: t.string().primaryKey(), listingId: t.string(), buyerId: t.string(), sellerId: t.string(),
  status: t.string(), expires: t.u64(), listingVersion: t.u32(), price: t.u32(),
});
const inventoryClaims = table({ name: 'inventory_claims' }, { listingId: t.string().primaryKey(), reservationId: t.string() });
const pickupRuns = table({ name: 'pickup_runs' }, {
  id: t.string().primaryKey(), buyerId: t.string().index('btree'), mode: t.string(), status: t.string(), phase: t.string(),
  currentStop: t.u32(), version: t.u32(), created: t.u64(),
});
const pickupStops = table({ name: 'pickup_stops', indexes: [
  { accessor: 'byRun', algorithm: 'btree', columns: ['runId', 'sequence'] },
  { accessor: 'bySeller', algorithm: 'btree', columns: ['sellerId', 'status'] },
]}, {
  id: t.string().primaryKey(), runId: t.string(), buyerId: t.string(), sellerId: t.string(), locationId: t.string(),
  sequence: t.u32(), proposed: t.u64(), windowEnd: t.u64(), status: t.string(), phase: t.string(),
});
const pickupStopItems = table({ name: 'pickup_stop_items' }, {
  id: t.string().primaryKey(), stopId: t.string().index('btree'), listingId: t.string(), reservationId: t.string(),
});
const pickupScheduleChanges = table({ name: 'pickup_schedule_changes' }, {
  id: t.string().primaryKey(), stopId: t.string().index('btree'), proposerId: t.string(), proposed: t.u64(), status: t.string(),
});
const conversations = table({ name: 'conversations' }, {
  id: t.string().primaryKey(), buyerId: t.string(), sellerId: t.string(), pinnedListingId: t.string(), summary: t.string(), sequence: t.u32(),
});
const conversationMembers = table({ name: 'conversation_members' }, {
  id: t.string().primaryKey(), conversationId: t.string(), userId: t.string().index('btree'), role: t.string(), lastRead: t.u32(),
});
const messages = table({ name: 'messages', indexes: [
  { accessor: 'byConversation', algorithm: 'btree', columns: ['conversationId', 'sequence'] },
]}, {
  id: t.string().primaryKey(), conversationId: t.string(), senderId: t.string(), sequence: t.u32(),
  operationId: t.string(), text: t.string(), mediaId: t.string(), listingId: t.string(), stopId: t.string(), created: t.u64(),
});
const paymentAttempts = table({ name: 'payment_attempts' }, {
  id: t.string().primaryKey(), buyerId: t.string().index('btree'), sellerId: t.string(), stopId: t.string().unique(),
  amount: t.u32(), status: t.string(), provider: t.string(), simulation: t.bool(),
});
const receipts = table({ name: 'receipts', indexes: [
  { accessor: 'byBuyer', algorithm: 'btree', columns: ['buyerId', 'completed'] },
  { accessor: 'bySeller', algorithm: 'btree', columns: ['sellerId', 'completed'] },
]}, {
  id: t.string().primaryKey(), buyerId: t.string(), sellerId: t.string(), stopId: t.string(), paymentId: t.string().unique(),
  paid: t.u32(), currency: t.string(), completed: t.u64(), simulation: t.bool(), sellerName: t.string(),
});
const receiptItems = table({ name: 'receipt_items' }, {
  id: t.string().primaryKey(), receiptId: t.string().index('btree'), listingId: t.string(),
  title: t.string(), price: t.u32(), retail: t.u32(), grams: t.u32(), media: t.string(), category: t.string(),
});
const impactMonthly = table({ name: 'impact_monthly' }, {
  id: t.string().primaryKey(), userId: t.string().index('btree'), month: t.string(), mode: t.string(),
  items: t.u32(), saved: t.u32(), grams: t.u32(), earnings: t.u32(),
});
const favorites = table({ name: 'favorites' }, {
  id: t.string().primaryKey(), userId: t.string().index('btree'), listingId: t.string(),
});
const follows = table({ name: 'follows' }, {
  id: t.string().primaryKey(), userId: t.string().index('btree'), kind: t.string(), target: t.string(),
});
const verificationRecords = table({ name: 'verification_records' }, {
  id: t.string().primaryKey(), userId: t.string().index('btree'), kind: t.string(), status: t.string(), source: t.string(), checked: t.u64(),
});
const ratings = table({ name: 'ratings' }, {
  receiptId: t.string().primaryKey(), reviewerId: t.string(), sellerId: t.string().index('btree'), score: t.u8(),
});
const sellerStats = table({ name: 'seller_stats' }, {
  userId: t.string().primaryKey(), ratingTotal: t.u32(), ratingCount: t.u32(), completed: t.u32(),
});
const servicePrincipals = table({ name: 'service_principals' }, { identity: t.identity().primaryKey(), role: t.string() });
const analysisJobs = table({ name: 'analysis_jobs' }, {
  id: t.string().primaryKey(), ownerId: t.string().index('btree'), listingId: t.string(), mediaId: t.string(),
  status: t.string(), provider: t.string(), suggestions: t.string(), error: t.string(),
});
const freshnessRequests = table({ name: 'freshness_requests' }, {
  id: t.string().primaryKey(), listingId: t.string(), requesterId: t.string(), sellerId: t.string().index('btree'), status: t.string(), created: t.u64(), responded: t.u64(),
});
const issueReports = table({ name: 'issue_reports' }, {
  id: t.string().primaryKey(), reporterId: t.string().index('btree'), stopId: t.string(), reason: t.string(), status: t.string(), created: t.u64(),
});
const paymentMethods = table({ name: 'payment_methods' }, {
  id: t.string().primaryKey(), userId: t.string().index('btree'), providerReference: t.string(), display: t.string(),
});
const referralCodes = table({ name: 'referral_codes' }, { code: t.string().primaryKey(), userId: t.string().unique() });
const referralRedemptions = table({ name: 'referral_redemptions' }, {
  id: t.string().primaryKey(), referrerId: t.string(), referredId: t.string().unique(), receiptId: t.string(), status: t.string(),
});
const notificationPreferences = table({ name: 'notification_preferences' }, {
  userId: t.string().primaryKey(), messages: t.bool(), pickups: t.bool(), discovery: t.bool(),
});
const notificationDevices = table({ name: 'notification_devices' }, {
  id: t.string().primaryKey(), userId: t.string().index('btree'), providerToken: t.string(),
});
const operationResults = table({ name: 'operation_results' }, {
  id: t.string().primaryKey(), actor: t.string(), fingerprint: t.string(), result: t.string(), created: t.u64(),
});
const scheduledTaskRecords = table({ name:'scheduled_tasks' }, {id:t.string().primaryKey(),due:t.u64().index('btree'),kind:t.string(),resourceId:t.string()});
export const scheduledTasks = table({ name: 'claim_expiry_tasks' }, {
  scheduledId:t.u64().primaryKey().autoInc(), id:t.string().unique(), scheduledAt:t.scheduleAt(), due: t.u64().index('btree'), kind: t.string(), resourceId: t.string(),
});
const seedVersions = table({ name: 'seed_versions' }, { id: t.string().primaryKey(), installed: t.u64(), count: t.u32() });
const configuration = table({ name: 'configuration' }, { id: t.string().primaryKey(), simulation: t.bool(), local: t.bool() });

const databaseOwner = table({ name: 'database_owner' }, { id: t.string().primaryKey(), identity: t.identity() });
const identifiers = table({name:'identifiers'},{id:t.string().primaryKey(),next:t.u64()});
const rateLimits = table({ name:'rate_limits' }, { userId:t.string().primaryKey(), window:t.u64(), count:t.u32() });
const db = schema({ identifiers, rateLimits, databaseOwner, users, userIdentities, userPreferences, listings, mediaAssets, listingMedia,
  pickupLocations, listingPickupWindows, listingAttestations, tags, listingTags, listingSearchTerms,
  searchTermStats, carts, cartItems, reservations, inventoryClaims, pickupRuns, pickupStops,
  pickupStopItems, pickupScheduleChanges, conversations, conversationMembers, messages,
  paymentAttempts, receipts, receiptItems, impactMonthly, favorites, follows, verificationRecords,
  ratings, sellerStats, servicePrincipals, analysisJobs, freshnessRequests, issueReports,
  paymentMethods, referralCodes, referralRedemptions, notificationPreferences, notificationDevices,
  operationResults, scheduledTasks:scheduledTaskRecords, scheduledExpiryTasks:scheduledTasks, seedVersions, configuration });
export default db;
