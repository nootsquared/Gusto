import { t, type InferSchema, type TransactionCtx, SenderError, Range } from 'spacetimedb/server';
import db, {scheduledTasks} from './schema';
import { Identity, ScheduleAt } from 'spacetimedb';
import { registeredClaims } from './auth';
export default db;
export const init = db.init(ctx => { ctx.db.databaseOwner.insert({ id:'owner', identity:ctx.sender }); });
type Ctx = TransactionCtx<InferSchema<typeof db>>;
const Request = t.object('APIRequest', {
  action: t.string(), operationId: t.string(), resourceId: t.string(), text: t.string(),
  version: t.u32(), value: t.u32(), enabled: t.bool(), cursor: t.string(),
});
const Result = t.object('APIResult', {
  apiVersion: t.u32(), serverTime: t.f64(), error: t.string(), payload: t.string(),
});
type RequestData = { action: string; operationId: string; resourceId: string; text: string; version: number; value: number; enabled: boolean; cursor: string };
const json = (value: unknown) => JSON.stringify(value, (_key, v) => typeof v === "bigint" ? Number(v) : v);
const stamp = (ctx: Ctx) => ctx.timestamp.microsSinceUnixEpoch / 1000n;
const now = (ctx: Ctx) => Number(ctx.timestamp.microsSinceUnixEpoch / 1000n);
function uid(ctx: Ctx): string {
  // Persistent allocation prevents identifier reuse across module restart/republish.
  const sequence=ctx.db.identifiers.id.find('global');
  const next=sequence?.next??1n;
  if(sequence)ctx.db.identifiers.id.update({...sequence,next:next+1n});
  else ctx.db.identifiers.insert({id:'global',next:next+1n});
  return `rescue-${next}`;
}
function fail(code: string): never { throw new SenderError(code); }
function actor(ctx: Ctx) {
  const row = ctx.db.userIdentities.identity.find(ctx.sender);
  if (!row || ctx.db.users.id.find(row.userId)?.status !== 'active') fail('unauthorized');
  return row.userId;
}
function owner(ctx: Ctx) { if (!ctx.db.databaseOwner.id.find('owner')?.identity.equals(ctx.sender)) fail('unauthorized'); }
function simulator(ctx: Ctx, role: string) {
  if (!ctx.db.configuration.id.find('runtime')?.simulation || ctx.db.servicePrincipals.identity.find(ctx.sender)?.role !== role) fail('unauthorized');
}
function listing(ctx: Ctx, id: string) { const row = ctx.db.listings.id.find(id); if (!row) fail('not_found'); return row; }
function ownedListing(ctx: Ctx, user: string, id: string) {
  const row = listing(ctx, id); if (row.sellerId !== user) fail('unauthorized'); return row;
}
function expired(ctx: Ctx, reservationId: string) {
  const row = ctx.db.reservations.id.find(reservationId);
  return !row || !['held', 'booked'].includes(row.status) || row.expires <= now(ctx);
}
function release(ctx: Ctx, reservationId: string, status = 'released') {
  const row = ctx.db.reservations.id.find(reservationId); if (!row || row.status === 'paid') return;
  ctx.db.reservations.id.update({ ...row, status });
  if (ctx.db.inventoryClaims.listingId.find(row.listingId)?.reservationId === row.id) ctx.db.inventoryClaims.listingId.delete(row.listingId);
  ctx.db.cartItems.id.delete(`${row.buyerId}:${row.listingId}`);
  for (const run of ctx.db.pickupRuns.buyerId.filter(row.buyerId)) {
    if (['draft', 'active'].includes(run.status)) {
      ctx.db.pickupRuns.id.update({ ...run, status: 'cancelled', phase: 'idle', version: run.version + 1 });
      for(const payment of ctx.db.paymentAttempts.buyerId.filter(row.buyerId)) if(payment.status==='pending' && ctx.db.pickupStops.id.find(payment.stopId)?.runId===run.id)ctx.db.paymentAttempts.id.update({...payment,status:'failed',provider:'reservation-released'});
    }
  }
}
function checkClaim(ctx: Ctx, reservationId: string) {
  if (expired(ctx, reservationId)) fail('expired');
  const r = ctx.db.reservations.id.find(reservationId)!;
  if (ctx.db.inventoryClaims.listingId.find(r.listingId)?.reservationId !== r.id) fail('unavailable');
  return r;
}
function claim(ctx: Ctx, id: string) {
  const existing = ctx.db.inventoryClaims.listingId.find(id);
  if (existing && expired(ctx, existing.reservationId)) { release(ctx, existing.reservationId, 'expired'); return null; }
  return existing;
}
function bumpCart(ctx: Ctx, user: string) {
  const c = ctx.db.carts.userId.find(user);
  if (c) ctx.db.carts.userId.update({ ...c, version: c.version + 1, updated: stamp(ctx) });
}
function mediaURL(ctx: Ctx, id: string) {
  const link = [...ctx.db.listingMedia.listingId.filter(id)].sort((a, b) => a.order - b.order)[0];
  const media = link && ctx.db.mediaAssets.id.find(link.mediaId);
  if (media?.visibility !== 'public') return '';
  // Sample photos ship with the iPhone app; real uploaded media uses a hosted reference.
  if (media.key.startsWith('data:image/jpeg;base64,')) return media.key;
  return media.key.startsWith('bundle:') ? media.key.slice(7) : `/media/${media.hash}/detail.jpg`;
}
function sellerProjection(ctx: Ctx, id: string) {
  const u = ctx.db.users.id.find(id)!;
  const loc = [...ctx.db.pickupLocations.sellerId.filter(id)][0];
  const stats = ctx.db.sellerStats.userId.find(id);
  return { id, name: u.name, rating: stats?.ratingCount ? stats.ratingTotal / stats.ratingCount : 0,
    pickups: stats?.completed ?? 0, responds: 'Local demo', student: [...ctx.db.verificationRecords.userId.filter(id)].some(v => v.kind === 'student' && v.status === 'verified'),
    area: loc?.area ?? '', latitude: loc?.latitude ?? 42.28, longitude: loc?.longitude ?? -83.74, avatarURL: u.avatar };
}
function listingProjection(ctx: Ctx, row: ReturnType<typeof listing>) {
  const windows = [...ctx.db.listingPickupWindows.listingId.filter(row.id)];
  const loc = windows[0] && ctx.db.pickupLocations.id.find(windows[0].locationId);
  return { id: row.id, name: row.title, price: row.price, retail: row.retail,
    distance: loc ? distance(42.28, -83.74, loc.latitude, loc.longitude) : 0,
    freshness: row.freshness, pickup: windows.some(w => w.start <= now(ctx) && w.end > now(ctx)) ? 'Available now · Pickup tonight' : 'Tomorrow',
    updated: new Date(Number(row.updated)).toISOString(), stale: now(ctx) - Number(row.updated) > 86400000,
    sellerID: row.sellerId, category: row.category, quantity: row.quantity, weight: row.grams / 453.59237,
    opened: row.opened, storage: row.storage, allergens: row.allergens, purchased: row.purchased,
    receipt: false, vegetarian: row.vegetarian, prepared: row.prepared, available: row.status === 'published',
    imageURL: mediaURL(ctx, row.id), version: row.version, windows: windows.map(w => ({ id: w.id, locationID: w.locationId, start: w.start, end: w.end, timezone: w.timezone })) };
}
function distance(a: number, b: number, c: number, d: number) {
  const rad = Math.PI / 180; const x = (d - b) * rad * Math.cos((a + c) * rad / 2); const y = (c - a) * rad;
  return Math.sqrt(x * x + y * y) * 3958.8;
}
function receiptsFor(ctx: Ctx, user: string, sales = false) {
  const rows = sales ? [...ctx.db.receipts.bySeller.filter(user)] : [...ctx.db.receipts.byBuyer.filter(user)];
  return rows.sort((a, b) => Number(b.completed - a.completed)).map(r => ({ ...r, seller: { ...sellerProjection(ctx, r.sellerId), name: r.sellerName },
    items: [...ctx.db.receiptItems.receiptId.filter(r.id)].map(i => ({
      id: i.listingId, name: i.title, price: i.price, retail: i.retail, weight: i.grams / 453.59237,
      imageURL: i.media, sellerID: r.sellerId, category: i.category,
    })) }));
}
function runProjection(ctx: Ctx, user: string) {
  const run = [...ctx.db.pickupRuns.buyerId.filter(user)].filter(r => ['draft', 'active', 'finished'].includes(r.status)).sort((a,b) => Number(b.created - a.created))[0];
  if (!run) return null;
  return { ...run, stops: [...ctx.db.pickupStops.byRun.filter(run.id)].sort((a,b) => a.sequence-b.sequence).map(s => ({ ...s,
    seller: sellerProjection(ctx, s.sellerId), items: [...ctx.db.pickupStopItems.stopId.filter(s.id)].map(i => listingProjection(ctx, listing(ctx, i.listingId))),
    privateLocation: s.status === 'confirmed' && [...ctx.db.pickupStopItems.stopId.filter(s.id)].every(i => !expired(ctx, i.reservationId)) ? { ...privateLocation(ctx, s.locationId), cacheUntil:Math.min(now(ctx)+900000,...[...ctx.db.pickupStopItems.stopId.filter(s.id)].map(i=>Number(ctx.db.reservations.id.find(i.reservationId)!.expires))) } : null,
  })) };
}
function privateLocation(ctx: Ctx, id: string) {
  const l = ctx.db.pickupLocations.id.find(id)!;
  return { address: l.address, instructions: l.instructions, latitude: l.exactLatitude, longitude: l.exactLongitude, cacheUntil: now(ctx) + 900000 };
}
function conversation(ctx: Ctx, a: string, b: string, pinned = '') {
  if (a === b || !ctx.db.users.id.find(b)) fail('invalid_transition');
  const id = [a,b].sort().join(':');
  let c = ctx.db.conversations.id.find(id);
  if (!c) {
    c = ctx.db.conversations.insert({ id, buyerId: a, sellerId: b, pinnedListingId: pinned, summary: '', sequence: 0 });
    for (const userId of [a,b]) ctx.db.conversationMembers.insert({ id: `${id}:${userId}`, conversationId: id, userId, role: userId === a ? 'buyer' : 'seller', lastRead: 0 });
  }
  return c;
}
function member(ctx: Ctx, user: string, id: string) {
  const m = ctx.db.conversationMembers.id.find(`${id}:${user}`); if (!m) fail('unauthorized'); return m;
}
function sendMessage(ctx: Ctx, user: string, id: string, text: string, operationId: string) {
  member(ctx, user, id);
  if (!text.trim() || text.length > 4000) fail('invalid_transition');
  const c = ctx.db.conversations.id.find(id)!;
  const m = ctx.db.messages.insert({ id: uid(ctx), conversationId: id, senderId: user, sequence: c.sequence + 1,
    operationId, text: text.trim(), mediaId: '', listingId: '', stopId: '', created: stamp(ctx) });
  ctx.db.conversations.id.update({ ...c, sequence: m.sequence, summary: m.text }); return m;
}
function tokens(text: string) { return [...new Set(text.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter(Boolean))]; }
function indexListing(ctx: Ctx, row: ReturnType<typeof listing>) {
  for (const p of ctx.db.listingSearchTerms.listingId.filter(row.id)) {
    ctx.db.listingSearchTerms.id.delete(p.id);
    const stat = ctx.db.searchTermStats.id.find(`${p.area}:${p.token}`);
    if (stat) ctx.db.searchTermStats.id.update({ ...stat, count: Math.max(0, stat.count - 1) });
  }
  if (row.status !== 'published') return;
  const labels=[...ctx.db.listingTags.listingId.filter(row.id)].map(l=>ctx.db.tags.id.find(l.tagId)?.label??'').join(' ');
  for (const token of tokens(`${labels} ${row.title} ${row.category} ${row.vegetarian ? 'vegetarian' : ''} ${row.opened ? '' : 'unopened'}`)) {
    ctx.db.listingSearchTerms.insert({ id: `${row.id}:${token}`, listingId: row.id, area: row.area, token, created: row.created, creationOrder: row.creationOrder });
    const id = `${row.area}:${token}`; const s = ctx.db.searchTermStats.id.find(id);
    if (s) ctx.db.searchTermStats.id.update({ ...s, count: s.count + 1 }); else ctx.db.searchTermStats.insert({ id, count: 1 });
  }
}
function discover(ctx: Ctx, q: RequestData) {
  const spec = JSON.parse(q.text || '{}') as { query?: string; area?: string; maxPrice?: number; freshness?: string[]; categories?: string[]; vegetarian?: boolean; unopened?: boolean; tonight?: boolean; tomorrow?: boolean; minimumRating?: number; distance?: number; latitude?: number; longitude?: number };
  const query = (spec.query || '').toLowerCase().replace(/\s+/g, ' ').trim();
  const area = spec.area || '';
  const normalized = json({ ...spec, query, area });
  let afterOrder = 0n, afterID = '';
  if (q.cursor) { const c = JSON.parse(q.cursor); if (c.spec !== normalized) fail('stale_version'); afterOrder = BigInt(c.order); afterID = c.id; }
  const price = query.match(/under\s*\$?(\d+(?:\.\d+)?)/);
  const maxPrice = Math.min(spec.maxPrice ?? 100000, price ? Math.round(Number(price[1]) * 100) - 1 : query.includes('cheap') ? 299 : 100000);
  const words = tokens(query.replace(/under\s*\$?\d+(?:\.\d+)?/g,'').replace(/north campus|tonight|tomorrow|\bcheap\b|\bfood\b|\bnear\b/g,'').replace(/\bdinner\b/g,'prepared'));
  const range = new Range<bigint>({tag:'included',value:afterOrder});
  const smallest = [...words].sort((a,b) => (ctx.db.searchTermStats.id.find(`${area}:${a}`)?.count ?? 0) - (ctx.db.searchTermStats.id.find(`${area}:${b}`)?.count ?? 0))[0];
  const source = smallest
    ? (area ? ctx.db.listingSearchTerms.byTerm.filter([area,smallest,range]) : ctx.db.listingSearchTerms.byGlobalTerm.filter([smallest,range]))
    : (area ? ctx.db.listings.byArea.filter([area,'published',range]) : ctx.db.listings.byPublished.filter(['published',range]));
  const iterator = source[Symbol.iterator]();
  const results: ReturnType<typeof listingProjection>[] = []; let scanned = 0;
  const limit = Math.min(q.value || (q.action === 'map' ? 100 : 30), q.action === 'map' ? 100 : 50);
  let lastOrder = afterOrder, lastID = afterID;
  while (scanned < 500 && results.length < limit) {
    const next = iterator.next(); if (next.done) break;
    const record = next.value;
    const l = 'listingId' in record ? ctx.db.listings.id.find(record.listingId) : record;
    if (!l) continue;
    if (l.creationOrder === afterOrder && l.id <= afterID) continue;
    scanned++; lastOrder = l.creationOrder; lastID = l.id;
    if (l.status !== 'published' || l.price > maxPrice || (spec.vegetarian && !l.vegetarian) || (spec.unopened && l.opened)) continue;
    if (spec.freshness?.length && !spec.freshness.includes(l.freshness)) continue;
    if (spec.categories?.length && !spec.categories.includes(l.category)) continue;
    const labels=[...ctx.db.listingTags.listingId.filter(l.id)].map(link=>ctx.db.tags.id.find(link.tagId)?.label??'').join(' ');
    if (!words.every(w => tokens(`${labels} ${l.title} ${l.category} ${l.vegetarian ? 'vegetarian' : ''} ${l.opened ? '' : 'unopened'}`).includes(w))) continue;
    const p = listingProjection(ctx, l); const s = sellerProjection(ctx, l.sellerId);
    const pickupLoc=p.windows[0] && ctx.db.pickupLocations.id.find(p.windows[0].locationID);
    p.distance = distance(spec.latitude ?? 42.28, spec.longitude ?? -83.74, pickupLoc?.latitude??s.latitude, pickupLoc?.longitude??s.longitude);
    if (p.distance > (spec.distance ?? 100) || s.rating < (spec.minimumRating ?? 0)) continue;
    if (query.includes('north campus') && !s.area.toLowerCase().includes('north')) continue;
    const windows = p.windows;
    if ((spec.tonight || query.includes('tonight')) && !windows.some(w => w.end > now(ctx) && w.start < now(ctx)+86400000)) continue;
    if ((spec.tomorrow || query.includes('tomorrow')) && !windows.some(w => w.start > now(ctx)+86400000)) continue;
    results.push(p);
  }
  return { listings: results, sellers: [...new Set(results.map(l=>l.sellerID))].map(id=>sellerProjection(ctx,id)),
    cursor: (scanned === 500 || results.length === limit) ? json({ spec: normalized, order: lastOrder.toString(), id:lastID }) : '', candidateScans: scanned,
    clusters: q.action === 'map' && (scanned === 500 || results.length === limit) ? [{ area, moreCandidatesMayExist:true }] : [] };
}
function activeRun(ctx: Ctx, user: string) {
  return [...ctx.db.pickupRuns.buyerId.filter(user)].find(r => r.status === 'active');
}
function currentStop(ctx: Ctx, user: string, resourceId: string) {
  const s = ctx.db.pickupStops.id.find(resourceId); if (!s) fail('not_found');
  if (s.buyerId !== user && s.sellerId !== user) fail('unauthorized');
  const r = ctx.db.pickupRuns.id.find(s.runId)!;
  if (r.status !== 'active' || r.currentStop !== s.sequence || !['confirmed','paid'].includes(s.status) || s.proposed>s.windowEnd) fail('invalid_transition');
  if (s.status !== 'paid') for (const i of ctx.db.pickupStopItems.stopId.filter(s.id)) checkClaim(ctx, i.reservationId);
  return { s, r };
}
function changePhase(ctx: Ctx, s: ReturnType<typeof currentStop>['s'], r: ReturnType<typeof currentStop>['r'], phase: string) {
  ctx.db.pickupStops.id.update({ ...s, phase }); ctx.db.pickupRuns.id.update({ ...r, phase, version: r.version+1 });
}
function invalidateDraft(ctx: Ctx, user: string) {
  for (const r of ctx.db.pickupRuns.buyerId.filter(user)) if (r.status === 'draft') ctx.db.pickupRuns.id.update({ ...r, status: 'cancelled', version: r.version+1 });
}
function process(ctx: Ctx, user: string, q: RequestData): unknown {
  switch (q.action) {
    case 'bootstrap': {
      for (const r of ctx.db.reservations.byBuyer.filter(user)) if (['held','booked'].includes(r.status) && r.expires <= now(ctx)) release(ctx,r.id,'expired');
      const items = [...ctx.db.cartItems.buyerId.filter(user)].filter(i => !i.reservationId || !expired(ctx, i.reservationId));
      return { user: ctx.db.users.id.find(user), preferences: ctx.db.userPreferences.userId.find(user),
        cart: items.map(i => i.listingId), cartListings: items.map(i => listingProjection(ctx,listing(ctx,i.listingId))),
        reservations: items.filter(i => i.reservationId).map(i => ctx.db.reservations.id.find(i.reservationId)),
        favorites: [...ctx.db.favorites.userId.filter(user)].map(f=>f.listingId),follows:[...ctx.db.follows.userId.filter(user)],
        savedListings: [...ctx.db.favorites.userId.filter(user)].map(f=>ctx.db.listings.id.find(f.listingId)).filter((l): l is ReturnType<typeof listing> => !!l && l.status === 'published').map(l=>listingProjection(ctx,l)),
        sellers: [...ctx.db.users.iter()].map(u=>sellerProjection(ctx,u.id)), run: runProjection(ctx,user),
        receipts: receiptsFor(ctx,user).slice(0,30), sales: receiptsFor(ctx,user,true).slice(0,30),
        ownListings: [...ctx.db.listings.bySeller.filter(user)].map(l=>listingProjection(ctx,l)),
        conversations: [...ctx.db.conversationMembers.userId.filter(user)].map(m=>ctx.db.conversations.id.find(m.conversationId)),
        monthly: [...ctx.db.impactMonthly.userId.filter(user)], simulation: ctx.db.configuration.id.find('runtime')?.simulation ?? false };
    }
    case 'feed': case 'search': case 'map': return discover(ctx,q);
    case 'detail': {
      const l = listing(ctx,q.resourceId); if (l.status !== 'published' && l.sellerId !== user) fail('not_found');
      return { listing: listingProjection(ctx,l), seller: sellerProjection(ctx,l.sellerId) };
    }
    case 'add_cart': {
      if (activeRun(ctx,user)) fail('invalid_transition');
      const l = listing(ctx,q.resourceId);
      if (l.status !== 'published' || l.sellerId === user) fail('unavailable');
      const id = `${user}:${l.id}`;
      const existing = ctx.db.cartItems.id.find(id);
      if (existing) return existing;
      const c = claim(ctx,l.id);
      if (c && checkClaim(ctx,c.reservationId).buyerId !== user) fail('unavailable');
      invalidateDraft(ctx,user);
      // An empty reservation ID is a saved cart item: no inventory claim, timer, or seller contact.
      const item = ctx.db.cartItems.insert({id,buyerId:user,listingId:l.id,reservationId:'',added:now(ctx)});
      bumpCart(ctx,user);
      return item;
    }
    case 'reserve': {
      if (activeRun(ctx,user)) fail('invalid_transition');
      const l = listing(ctx,q.resourceId); if (l.status !== 'published' || l.sellerId === user) fail('unavailable');
      const c = claim(ctx,l.id);
      if (c) { const r=checkClaim(ctx,c.reservationId); if (r.buyerId !== user) fail('unavailable'); return r; }
      invalidateDraft(ctx,user);
      const r = ctx.db.reservations.insert({ id: uid(ctx), listingId:l.id, buyerId:user, sellerId:l.sellerId, status:'held',
        expires:stamp(ctx)+1800000n, listingVersion:l.version, price:l.price });
      ctx.db.inventoryClaims.insert({ listingId:l.id,reservationId:r.id });
      const cartID = `${user}:${l.id}`;
      const saved = ctx.db.cartItems.id.find(cartID);
      if (saved) ctx.db.cartItems.id.update({...saved,reservationId:r.id});
      else ctx.db.cartItems.insert({ id:cartID,buyerId:user,listingId:l.id,reservationId:r.id,added:now(ctx) });
      ctx.db.scheduledExpiryTasks.insert({ scheduledId:0n,id:r.id,scheduledAt:ScheduleAt.time(r.expires*1000n),due:r.expires,kind:'reservation',resourceId:r.id }); bumpCart(ctx,user); return r;
    }
    case 'release': {
      if (activeRun(ctx,user)) fail('invalid_transition');
      const c=ctx.db.cartItems.id.find(`${user}:${q.resourceId}`);
      if (c?.reservationId) release(ctx,c.reservationId);
      else if (c) ctx.db.cartItems.id.delete(c.id);
      invalidateDraft(ctx,user); bumpCart(ctx,user); return {};
    }
    case 'favorite': {
      const l=listing(ctx,q.resourceId); if(l.status !== 'published' && l.sellerId !== user) fail('not_found');
      const id=`${user}:${q.resourceId}`;
      if(q.enabled && !ctx.db.favorites.id.find(id))ctx.db.favorites.insert({id,userId:user,listingId:q.resourceId});
      if(!q.enabled)ctx.db.favorites.id.delete(id); return {};
    }
    case 'preferences': {
      const p=ctx.db.userPreferences.userId.find(user)!;
      if(q.version !== p.version)fail('stale_version');
      ctx.db.userPreferences.userId.update({...p,smartAlerts:q.enabled,vegetarian:q.value===1,version:p.version+1});return {};
    }
    case 'follow': {
      const id=`${user}:${q.text}:${q.resourceId}`;
      if(!['seller','category','tag','price'].includes(q.text))fail('invalid_transition');
      if(q.enabled && !ctx.db.follows.id.find(id))ctx.db.follows.insert({id,userId:user,kind:q.text,target:q.resourceId});
      if(!q.enabled)ctx.db.follows.id.delete(id);return {};
    }
    case 'profile': {
      if (!q.text.trim() || q.text.length>80) fail('invalid_transition');
      ctx.db.users.id.update({...ctx.db.users.id.find(user)!,name:q.text.trim()});return {};
    }
    case 'history': {
      const rows=receiptsFor(ctx,user,q.enabled); const offset=Number(q.cursor || 0);
      return {receipts:rows.slice(offset,offset+30),cursor:offset+30<rows.length?String(offset+30):''};
    }
    case 'messages': {
      member(ctx,user,q.resourceId); const after=Number(q.cursor||0);
      const bounds=q.enabled?new Range<number>(undefined,{tag:'excluded',value:after}):new Range<number>({tag:'excluded',value:after});
      const rows=[...ctx.db.messages.byConversation.filter([q.resourceId,bounds])].sort((a,b)=>a.sequence-b.sequence);
      const page=q.enabled||after===0?rows.slice(-30):rows.slice(0,30);
      return { messages:page,cursor:rows.length>30?String(q.enabled||after===0?page[0].sequence:page[page.length-1].sequence):'',lastSequence:page[page.length-1]?.sequence??after };
    }
    case 'send': {
      const c=q.resourceId.includes(':') ? (member(ctx,user,q.resourceId),ctx.db.conversations.id.find(q.resourceId)!) : conversation(ctx,user,q.resourceId);
      return sendMessage(ctx,user,c.id,q.text,q.operationId);
    }
    case 'mark_read': {
      const m=member(ctx,user,q.resourceId); const c=ctx.db.conversations.id.find(m.conversationId)!;
      ctx.db.conversationMembers.id.update({...m,lastRead:Math.min(q.value,c.sequence)});return {};
    }
    case 'freshness': {
      const l=listing(ctx,q.resourceId); if(l.status !== 'published')fail('unavailable');
      return ctx.db.freshnessRequests.insert({id:uid(ctx),listingId:l.id,requesterId:user,sellerId:l.sellerId,status:'pending',created:stamp(ctx),responded:0n});
    }
    case 'respond_freshness': {
      const f=ctx.db.freshnessRequests.id.find(q.resourceId);if(!f)fail('not_found');if(f.sellerId!==user)fail('unauthorized');
      ctx.db.freshnessRequests.id.update({...f,status:'responded',responded:stamp(ctx)});
      const l=listing(ctx,f.listingId);ctx.db.listings.id.update({...l,updated:stamp(ctx)});return {};
    }
    case 'inventory': {
      const items=[...ctx.db.foodInventory.ownerId.filter(user)].sort((a,b)=>Number(b.scannedAt-a.scannedAt));
      const readings=[...ctx.db.storageReadings.ownerId.filter(user)].filter(r=>Number(r.recordedAt)>=now(ctx)-259200000)
        .sort((a,b)=>Number(b.recordedAt-a.recordedAt)).slice(0,500);
      return {items,readings};
    }
    case 'inventory_save': {
      const old=ctx.db.foodInventory.id.find(q.resourceId);
      if(old && old.ownerId!==user)fail('unauthorized');
      const f=JSON.parse(q.text);
      if(!q.resourceId || !f.name?.trim() || f.name.length>100 || !f.quantity?.trim() || f.quantity.length>100 ||
        typeof f.photoBase64!=='string' || f.photoBase64.length>90000 || !/^[A-Za-z0-9+/=]*$/.test(f.photoBase64) ||
        !['Counter','Fridge','Pantry'].includes(f.storage) || !['Not assessed','Unripe','Ripe','Use soon'].includes(f.condition) ||
        typeof f.variety!=='string' || f.variety.length>100 || typeof f.deviceID!=='string' || f.deviceID.length>100 ||
        !Number.isFinite(f.confidence) || f.confidence<0 || f.confidence>1)fail('invalid_transition');
      if(!old && [...ctx.db.foodInventory.ownerId.filter(user)].length>=50)fail('invalid_transition');
      if(old?.listingID)fail('invalid_transition');
      const item={id:q.resourceId,ownerId:user,name:f.name.trim(),variety:f.variety.trim(),category:'Produce',
        condition:f.condition,quantity:f.quantity.trim(),storage:f.storage,photoBase64:f.photoBase64,
        identification:f.identification==='Apple Vision'?'Apple Vision':'Manual review',confidence:f.confidence,
        scannedAt:old?.scannedAt??stamp(ctx),listingID:old?.listingID??'',deviceID:f.deviceID};
      if(old)ctx.db.foodInventory.id.update(item);else ctx.db.foodInventory.insert(item);return item;
    }
    case 'inventory_remove': case 'inventory_unlist': {
      const item=ctx.db.foodInventory.id.find(q.resourceId);if(!item)fail('not_found');if(item.ownerId!==user)fail('unauthorized');
      if(item.listingID){const l=ownedListing(ctx,user,item.listingID);if(claim(ctx,l.id)||l.status==='sold')fail('unavailable');
        ctx.db.listings.id.update({...l,status:'archived',version:l.version+1});indexListing(ctx,{...l,status:'archived'});}
      if(q.action==='inventory_unlist')ctx.db.foodInventory.id.update({...item,listingID:''});
      else {ctx.db.foodInventory.id.delete(item.id);for(const r of ctx.db.storageReadings.ownerId.filter(user))if(r.itemID===item.id)ctx.db.storageReadings.id.delete(r.id);}
      return {};
    }
    case 'sensor_reading': {
      const item=ctx.db.foodInventory.id.find(q.resourceId);if(!item)fail('not_found');if(item.ownerId!==user)fail('unauthorized');
      const r=JSON.parse(q.text);
      if(!item.deviceID || r.deviceID!==item.deviceID || !Number.isFinite(r.temperature)||r.temperature< -40||r.temperature>85 ||
        !Number.isFinite(r.humidity)||r.humidity<0||r.humidity>100||!Number.isFinite(r.light)||r.light<0||r.light>200000)fail('invalid_transition');
      // Phone ingestion timestamps are server-authoritative; the firmware adapter will submit per-item samples.
      const reading=ctx.db.storageReadings.insert({id:uid(ctx),ownerId:user,itemID:item.id,deviceID:item.deviceID,
        temperature:r.temperature,humidity:r.humidity,light:r.light,recordedAt:stamp(ctx)});
      const old=[...ctx.db.storageReadings.ownerId.filter(user)].sort((a,b)=>Number(b.recordedAt-a.recordedAt));
      for(const row of old.slice(500))ctx.db.storageReadings.id.delete(row.id);return reading;
    }
    case 'inventory_publish': {
      const f=ctx.db.foodInventory.id.find(q.resourceId);if(!f)fail('not_found');if(f.ownerId!==user)fail('unauthorized');
      if(f.listingID)fail('invalid_transition');const p=JSON.parse(q.text);
      if(!Number.isInteger(p.price)||p.price<=0||p.price>100000||typeof p.allergens!=='string'||!p.allergens.trim()||p.allergens.length>500 ||
        p.safeStorage!==true||p.accurateCondition!==true||p.noSpoilage!==true||p.allergensDeclared!==true || !f.photoBase64 ||
        typeof p.pickupAddress!=='string'||!p.pickupAddress.trim()||p.pickupAddress.length>500||
        !Number.isFinite(p.latitude)||Math.abs(p.latitude)>90||!Number.isFinite(p.longitude)||Math.abs(p.longitude)>180||
        !Number.isSafeInteger(p.start)||!Number.isSafeInteger(p.end)||p.end<=p.start||p.end<=now(ctx)||p.end>now(ctx)+259200000)fail('invalid_transition');
      const id=uid(ctx),locId=uid(ctx),mediaId=uid(ctx),area=p.pickupAddress.trim();
      ctx.db.pickupLocations.insert({id:locId,sellerId:user,area:'Nearby pickup',latitude:Math.round(p.latitude*100)/100,
        longitude:Math.round(p.longitude*100)/100,exactLatitude:p.latitude,exactLongitude:p.longitude,address:area,instructions:'Arrange pickup in chat'});
      const l=ctx.db.listings.insert({id,sellerId:user,title:f.variety?f.variety+' '+f.name:f.name,description:'Identified from a photo and reviewed by the seller.',
        category:f.category,quantity:f.quantity,price:p.price,retail:p.price,grams:0,freshness:f.condition==='Use soon'?'Use Soon':'Good',
        opened:false,prepared:false,storage:f.storage,allergens:p.allergens.trim(),vegetarian:true,purchased:'Seller supplied',bestBy:'',status:'published',area:'Nearby pickup',
        version:1,created:stamp(ctx),creationOrder:9007199254740991n-stamp(ctx),updated:stamp(ctx)});
      ctx.db.mediaAssets.insert({id:mediaId,ownerId:user,key:'data:image/jpeg;base64,'+f.photoBase64,hash:mediaId,mime:'image/jpeg',width:0,height:0,visibility:'public',state:'ready',created:stamp(ctx)});
      ctx.db.listingMedia.insert({id:uid(ctx),listingId:id,mediaId,role:'cover',order:0});
      ctx.db.listingPickupWindows.insert({id:uid(ctx),listingId:id,locationId:locId,start:BigInt(p.start),end:BigInt(p.end),timezone:'America/Detroit'});
      ctx.db.listingAttestations.insert({id:uid(ctx),listingId:id,version:1,sellerId:user,safeStorage:true,accurateCondition:true,noSpoilage:true,allergensDeclared:true,confirmed:stamp(ctx)});
      ctx.db.foodInventory.id.update({...f,listingID:id});indexListing(ctx,l);return {id};
    }
    case 'draft': {
      const id=uid(ctx);ctx.db.listings.insert({id,sellerId:user,title:'',description:'',category:'Breakfast',quantity:'1 package',price:0,retail:899,grams:363,
        freshness:'Fresh',opened:false,prepared:false,storage:'Pantry',allergens:'Oats, almonds',vegetarian:true,purchased:'Today',bestBy:'',status:'draft',area:'Linden Park',version:1,created:stamp(ctx),creationOrder:9007199254740991n-stamp(ctx),updated:stamp(ctx)});
      return {id,version:1};
    }
    case 'edit': {
      const l=ownedListing(ctx,user,q.resourceId);if(q.version!==l.version)fail('stale_version');
      const fields=JSON.parse(q.text) as {title:string;price:number;freshness:string;description?:string};
      if(!fields.title.trim()||fields.title.length>200||!Number.isInteger(fields.price)||fields.price<=0||fields.price>100000||!['Fresh','Good','Use Soon'].includes(fields.freshness))fail('invalid_transition');
      if(claim(ctx,l.id) && (l.price!==fields.price || l.freshness!==fields.freshness || l.title!==fields.title))fail('unavailable');
      const updated={...l,title:fields.title.trim(),price:fields.price,freshness:fields.freshness,description:fields.description??l.description,version:l.version+1,updated:stamp(ctx)};
      ctx.db.listings.id.update(updated);indexListing(ctx,updated);return {id:l.id,version:updated.version};
    }
    case 'attach_demo_media': {
      const l=ownedListing(ctx,user,q.resourceId);if(l.status!=='draft')fail('invalid_transition');
      if(!ctx.db.configuration.id.find('runtime')?.simulation)fail('service_unavailable');
      const source=ctx.db.mediaAssets.id.find('seed-gran');if(!source)fail('service_unavailable');
      const id=uid(ctx);ctx.db.mediaAssets.insert({...source,id,ownerId:user,visibility:'private',created:stamp(ctx)});
      ctx.db.listingMedia.insert({id:uid(ctx),listingId:l.id,mediaId:id,role:'cover',order:0});return {mediaId:id};
    }
    case 'analysis': {
      const l=ownedListing(ctx,user,q.resourceId);const media=[...ctx.db.listingMedia.listingId.filter(l.id)][0];if(!media)fail('invalid_transition');
      return ctx.db.analysisJobs.insert({id:uid(ctx),ownerId:user,listingId:l.id,mediaId:media.mediaId,status:'queued',provider:'',suggestions:'',error:''});
    }
    case 'publish': {
      const l=ownedListing(ctx,user,q.resourceId);if(l.version!==q.version)fail('stale_version');if(l.status!=='draft')fail('invalid_transition');
      const safety=JSON.parse(q.text) as { safeStorage:boolean;accurateCondition:boolean;noSpoilage:boolean;allergensDeclared:boolean;pickupStart?:number;pickupEnd?:number };
      if(safety.safeStorage!==true||safety.accurateCondition!==true||safety.noSpoilage!==true||safety.allergensDeclared!==true||!l.title||!l.price||!l.quantity||!l.storage||!l.allergens)fail('invalid_transition');
      const media=[...ctx.db.listingMedia.listingId.filter(l.id)];if(!media.length||!media.every(m=>ctx.db.mediaAssets.id.find(m.mediaId)?.ownerId===user))fail('unauthorized');
      // The owner chooses a window; the server validates UTC timing and assigns the location relationship.
      const loc=[...ctx.db.pickupLocations.sellerId.filter(user)][0];if(!loc)fail('invalid_transition');
      const start=safety.pickupStart??now(ctx),end=safety.pickupEnd??now(ctx)+86400000;
      if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||end<=now(ctx)||end<=start||end>now(ctx)+259200000)fail('invalid_transition');
      ctx.db.listingPickupWindows.insert({id:uid(ctx),listingId:l.id,locationId:loc.id,start:BigInt(start),end:BigInt(end),timezone:'America/Detroit'});
      ctx.db.listingAttestations.insert({id:uid(ctx),listingId:l.id,version:l.version,sellerId:user,safeStorage:true,accurateCondition:true,noSpoilage:true,allergensDeclared:true,confirmed:stamp(ctx)});
      for(const link of media){const m=ctx.db.mediaAssets.id.find(link.mediaId)!;ctx.db.mediaAssets.id.update({...m,visibility:'public'});}
      const published={...l,status:'published',updated:stamp(ctx),version:l.version+1};ctx.db.listings.id.update(published);indexListing(ctx,published);return {id:l.id,version:published.version};
    }
    case 'archive': {
      const l=ownedListing(ctx,user,q.resourceId);if(l.version!==q.version)fail('stale_version');if(claim(ctx,l.id))fail('unavailable');
      ctx.db.listings.id.update({...l,status:'archived',version:l.version+1});indexListing(ctx,{...l,status:'archived'});return {};
    }
    case 'plan': {
      if(activeRun(ctx,user))fail('invalid_transition');
      const savedItems=[...ctx.db.cartItems.buyerId.filter(user)];if(!savedItems.length)fail('invalid_transition');
      // Confirmation reserves the entire cart in this transaction; failure rolls back every claim.
      for (const i of savedItems) if (!i.reservationId) process(ctx,user,{...q,action:'reserve',resourceId:i.listingId});
      const items=[...ctx.db.cartItems.buyerId.filter(user)];
      for(const i of items)checkClaim(ctx,i.reservationId);
      invalidateDraft(ctx,user);
      const run=ctx.db.pickupRuns.insert({id:uid(ctx),buyerId:user,mode:q.text||'Fastest',status:'draft',phase:'idle',currentStop:0,version:1,created:stamp(ctx)});
      const groups=new Map<string,typeof items>();
      for(const i of items){const l=listing(ctx,i.listingId);const w=[...ctx.db.listingPickupWindows.listingId.filter(l.id)].find(w=>w.end>now(ctx));if(!w)fail('expired');
        const key=`${l.sellerId}:${w.locationId}`;groups.set(key,[...(groups.get(key)||[]),i]);}
      let lat=42.28,lon=-83.74,proposed=now(ctx)+300000,seq=0;
      const remaining=[...groups.values()];
      while(remaining.length){remaining.sort((a,b)=>{
        const wa=[...ctx.db.listingPickupWindows.listingId.filter(a[0].listingId)][0];const wb=[...ctx.db.listingPickupWindows.listingId.filter(b[0].listingId)][0];
        const la=ctx.db.pickupLocations.id.find(wa.locationId)!;const lb=ctx.db.pickupLocations.id.find(wb.locationId)!;
        const da=distance(lat,lon,la.latitude,la.longitude),dbb=distance(lat,lon,lb.latitude,lb.longitude);
        const costA=q.text==='Fastest'?Math.max(da/15*3600000,Number(wa.start)-proposed):da;
        const costB=q.text==='Fastest'?Math.max(dbb/15*3600000,Number(wb.start)-proposed):dbb;
        return (q.text==='Best timing'?Number(wa.end-wb.end):costA-costB)||a[0].listingId.localeCompare(b[0].listingId);
      });const group=remaining.shift()!;const l=listing(ctx,group[0].listingId);const windows=group.map(i=>[...ctx.db.listingPickupWindows.listingId.filter(i.listingId)][0]);
        const w=windows[0];const loc=ctx.db.pickupLocations.id.find(w.locationId)!;
        proposed=Math.max(proposed+Math.ceil(distance(lat,lon,loc.latitude,loc.longitude)/15*60)*60000,...windows.map(w=>Number(w.start)));
        const end=Math.min(...windows.map(w=>Number(w.end)));if(proposed>end)fail('unavailable');
        const stop=ctx.db.pickupStops.insert({id:uid(ctx),runId:run.id,buyerId:user,sellerId:l.sellerId,locationId:loc.id,sequence:seq++,proposed:BigInt(Math.round(proposed)),windowEnd:BigInt(end),status:'unconfirmed',phase:'idle'});
        for(const i of group)ctx.db.pickupStopItems.insert({id:uid(ctx),stopId:stop.id,listingId:i.listingId,reservationId:i.reservationId});
        lat=loc.latitude;lon=loc.longitude;proposed+=300000;
      }
      return runProjection(ctx,user);
    }
    case 'coordinate': {
      const r=ctx.db.pickupRuns.id.find(q.resourceId);if(!r)fail('not_found');if(r.buyerId!==user)fail('unauthorized');if(r.status!=='draft')fail('invalid_transition');
      for(const s of ctx.db.pickupStops.byRun.filter(r.id)){
        for(const i of ctx.db.pickupStopItems.stopId.filter(s.id))checkClaim(ctx,i.reservationId);
        ctx.db.pickupStops.id.update({...s,status:'waiting'});const c=conversation(ctx,user,s.sellerId);
        sendMessage(ctx,user,c.id,`Can you confirm pickup at ${new Date(Number(s.proposed)).toISOString()}?`,q.operationId);
      }return {};
    }
    case 'confirm': {
      const s=ctx.db.pickupStops.id.find(q.resourceId);if(!s)fail('not_found');if(s.sellerId!==user)fail('unauthorized');
      const r=ctx.db.pickupRuns.id.find(s.runId)!;if(r.status!=='draft'||!['waiting','unconfirmed'].includes(s.status))fail('invalid_transition');
      if(s.proposed>s.windowEnd||s.windowEnd<now(ctx))fail('expired');
      for(const i of ctx.db.pickupStopItems.stopId.filter(s.id)){const reservation=checkClaim(ctx,i.reservationId);ctx.db.reservations.id.update({...reservation,status:'booked',expires:s.windowEnd+900000n});
        const task=ctx.db.scheduledExpiryTasks.id.find(reservation.id);if(task)ctx.db.scheduledExpiryTasks.scheduledId.update({...task,due:s.windowEnd+900000n,scheduledAt:ScheduleAt.time((s.windowEnd+900000n)*1000n)});}
      ctx.db.pickupStops.id.update({...s,status:'confirmed'});return {};
    }
    case 'schedule': {
      const s=ctx.db.pickupStops.id.find(q.resourceId);if(!s)fail('not_found');if(s.buyerId!==user&&s.sellerId!==user)fail('unauthorized');
      const r=ctx.db.pickupRuns.id.find(s.runId)!;if(!['draft','active'].includes(r.status)||['paid','skipped'].includes(s.status))fail('invalid_transition');
      const proposed=Number(q.text);if(!Number.isFinite(proposed)||proposed<now(ctx)||proposed>s.windowEnd)fail('invalid_transition');
      return ctx.db.pickupScheduleChanges.insert({id:uid(ctx),stopId:s.id,proposerId:user,proposed:BigInt(Math.round(proposed)),status:'pending'});
    }
    case 'accept_schedule': {
      const c=ctx.db.pickupScheduleChanges.id.find(q.resourceId);if(!c)fail('not_found');const s=ctx.db.pickupStops.id.find(c.stopId)!;
      if((s.buyerId!==user&&s.sellerId!==user)||c.proposerId===user)fail('unauthorized');if(c.status!=='pending'||c.proposed>s.windowEnd)fail('invalid_transition');
      const delta=c.proposed-s.proposed;
      for(const stop of ctx.db.pickupStops.byRun.filter(s.runId))if(stop.sequence>=s.sequence&&!['paid','skipped'].includes(stop.status)){
        const proposed=stop.proposed+delta;const status=proposed>stop.windowEnd?'waiting':stop.status;
        ctx.db.pickupStops.id.update({...stop,proposed,status});
      }
      ctx.db.pickupScheduleChanges.id.update({...c,status:'accepted'});return {};
    }
    case 'start': {
      const r=ctx.db.pickupRuns.id.find(q.resourceId);if(!r)fail('not_found');if(r.buyerId!==user)fail('unauthorized');if(r.status!=='draft')fail('invalid_transition');
      const stops=[...ctx.db.pickupStops.byRun.filter(r.id)];if(!stops.length||stops.some(s=>s.status!=='confirmed'||s.proposed>s.windowEnd))fail('invalid_transition');
      for(const s of stops)for(const i of ctx.db.pickupStopItems.stopId.filter(s.id))checkClaim(ctx,i.reservationId);
      ctx.db.pickupRuns.id.update({...r,status:'active',phase:'enroute',version:r.version+1});ctx.db.pickupStops.id.update({...stops[0],phase:'enroute'});return {};
    }
    case 'arrive': case 'announce': case 'handoff': case 'verify': {
      const {s,r}=currentStop(ctx,user,q.resourceId);
      if(q.action==='handoff'){if(s.sellerId!==user)fail('unauthorized');if(r.phase!=='waiting')fail('invalid_transition');changePhase(ctx,s,r,'verifying');}
      else {if(s.buyerId!==user)fail('unauthorized');const transitions:Record<string,[string,string]>={arrive:['enroute','arrived'],announce:['arrived','waiting'],verify:['verifying','payment']};
        const [from,to]=transitions[q.action];if(r.phase!==from)fail('invalid_transition');changePhase(ctx,s,r,to);}
      return {};
    }
    case 'payment': {
      const {s,r}=currentStop(ctx,user,q.resourceId);if(s.buyerId!==user)fail('unauthorized');
      const existing=ctx.db.paymentAttempts.stopId.find(s.id);if(existing && existing.status !== 'failed')return existing;
      if(r.phase!=='payment')fail('invalid_transition');
      if(!ctx.db.configuration.id.find('runtime')?.simulation)fail('service_unavailable');
      const amount=[...ctx.db.pickupStopItems.stopId.filter(s.id)].reduce((sum,i)=>sum+checkClaim(ctx,i.reservationId).price,0);
      const paymentRow={id:existing?.id??uid(ctx),buyerId:user,sellerId:s.sellerId,stopId:s.id,amount,status:'pending',provider:'',simulation:true};
      const attempt=existing?(ctx.db.paymentAttempts.id.update(paymentRow),paymentRow):ctx.db.paymentAttempts.insert(paymentRow);
      changePhase(ctx,s,r,'paying');return attempt;
    }
    case 'issue': case 'cancel': {
      const {s,r}=currentStop(ctx,user,q.resourceId);if(s.buyerId!==user)fail('unauthorized');
      if(!['enroute','arrived','waiting','verifying','payment'].includes(r.phase))fail('invalid_transition');
      ctx.db.issueReports.insert({id:uid(ctx),reporterId:user,stopId:s.id,reason:q.text||'Cancelled',status:'open',created:stamp(ctx)});
      if(q.action==='issue'){
        ctx.db.pickupStops.id.update({...s,status:'skipped'});
        for(const i of ctx.db.pickupStopItems.stopId.filter(s.id))release(ctx,i.reservationId);
        const next=[...ctx.db.pickupStops.byRun.filter(r.id)].find(stop=>stop.sequence===s.sequence+1);
        if(next){ctx.db.pickupRuns.id.update({...r,status:'active',phase:'enroute',currentStop:next.sequence,version:r.version+1});ctx.db.pickupStops.id.update({...next,phase:'enroute'});}
        else ctx.db.pickupRuns.id.update({...r,status:'finished',phase:'finished',version:r.version+1});
      }else{
        for(const stop of ctx.db.pickupStops.byRun.filter(r.id))if(stop.status!=='paid'){
          ctx.db.pickupStops.id.update({...stop,status:'skipped'});for(const i of ctx.db.pickupStopItems.stopId.filter(stop.id))release(ctx,i.reservationId);
        }
        ctx.db.pickupRuns.id.update({...r,status:'cancelled',phase:'idle',version:r.version+1});
      }return {};
    }
    case 'advance': {
      const {s,r}=currentStop(ctx,user,q.resourceId);if(s.buyerId!==user)fail('unauthorized');if(r.phase!=='rescued')fail('invalid_transition');
      const next=[...ctx.db.pickupStops.byRun.filter(r.id)].find(s=>s.sequence===r.currentStop+1);
      if(next){ctx.db.pickupRuns.id.update({...r,currentStop:next.sequence,phase:'enroute',version:r.version+1});ctx.db.pickupStops.id.update({...next,phase:'enroute'});}
      else ctx.db.pickupRuns.id.update({...r,status:'finished',phase:'finished',version:r.version+1});return {};
    }
    case 'finish': {
      const r=ctx.db.pickupRuns.id.find(q.resourceId);if(!r)fail('not_found');if(r.buyerId!==user)fail('unauthorized');if(r.status!=='finished')fail('invalid_transition');
      ctx.db.pickupRuns.id.update({...r,status:'closed',phase:'idle',version:r.version+1});return {};
    }
    case 'seller_activity': return { stops:[...ctx.db.pickupStops.bySeller.filter(user)].filter(s=>['draft','active'].includes(ctx.db.pickupRuns.id.find(s.runId)?.status??'')).map(s=>({...s,privateLocation:privateLocation(ctx,s.locationId)})),
      freshness:[...ctx.db.freshnessRequests.sellerId.filter(user)], jobs:[...ctx.db.analysisJobs.ownerId.filter(user)] };
    case 'media': {
      const m=ctx.db.mediaAssets.id.find(q.resourceId);if(!m)fail('not_found');
      if(m.visibility!=='public' && m.ownerId!==user)fail('unauthorized');return {key:m.key,hash:m.hash,mime:m.mime};
    }
    case 'rate': {
      const receipt=ctx.db.receipts.id.find(q.resourceId);if(!receipt)fail('not_found');if(receipt.buyerId!==user)fail('unauthorized');
      if(q.value<1||q.value>5||ctx.db.ratings.receiptId.find(receipt.id))fail('invalid_transition');
      ctx.db.ratings.insert({receiptId:receipt.id,reviewerId:user,sellerId:receipt.sellerId,score:q.value});
      const stats=ctx.db.sellerStats.userId.find(receipt.sellerId)!;ctx.db.sellerStats.userId.update({...stats,ratingTotal:stats.ratingTotal+q.value,ratingCount:stats.ratingCount+1});return {};
    }
    case 'enroll_card': case 'redeem_referral': case 'register_push': case 'verify_account': fail('service_unavailable');
    default: fail('not_found');
  }
}
const reads=new Set(['bootstrap','feed','search','map','detail','history','messages','seller_activity','media','inventory']);
export const api = db.procedure({ request: Request }, Result, (ctx, { request }) => {
  try {
    return ctx.withTx(tx => {
      const user=actor(tx);let result:unknown;
      const rate=tx.db.rateLimits.userId.find(user),window=stamp(tx)/60000n;
      if(rate?.window===window && rate.count>=240)fail('rate_limited');
      const updatedRate={userId:user,window,count:rate?.window===window?rate.count+1:1};
      if(rate)tx.db.rateLimits.userId.update(updatedRate);else tx.db.rateLimits.insert(updatedRate);
      if(request.text.length>(request.action==='inventory_save'?110000:16000) || request.resourceId.length>200 || request.cursor.length>20000)fail('invalid_transition');
      if(!reads.has(request.action)){
        if(!request.operationId || request.operationId.length>100)fail('invalid_transition');
        const id=`${user}:${request.operationId}`, fingerprint=json(request);
        const old=tx.db.operationResults.id.find(id);
        if(old){if(old.fingerprint!==fingerprint)fail('stale_version');return {apiVersion:1,serverTime:now(tx),error:'',payload:old.result};}
        result=process(tx,user,request);const payload=json(result);
        tx.db.operationResults.insert({id,actor:user,fingerprint,result:payload,created:stamp(tx)});
        return {apiVersion:1,serverTime:now(tx),error:'',payload};
      }
      result=process(tx,user,request);return {apiVersion:1,serverTime:now(tx),error:'',payload:json(result)};
    });
  } catch(error) { const text=String(error);const code=['unauthorized','not_found','unavailable','expired','stale_version','invalid_transition','service_unavailable','rate_limited'].find(c=>text.includes(c))??'service_unavailable';return {apiVersion:1,serverTime:Number(ctx.timestamp.microsSinceUnixEpoch/1000n),error:code,payload:'{}'}; }
});

export const registerProfile = db.procedure({ token: t.string() }, Result, (ctx, { token }) => {
  try {
    if (!token || token.length > 16000) fail('unauthorized');
    // HTTP procedure calls do not expose JWT claims through senderAuth in SDK 2.10.
    // Verify the supplied token belongs to the authenticated caller before inspecting claims.
    const verified = ctx.http.fetch(
      `https://maincloud.spacetimedb.com/v1/identity/${ctx.sender.toHexString()}/verify`,
      { headers: { Authorization: `Bearer ${token}` } });
    if (verified.status !== 204) fail('unauthorized');
    const claims = registeredClaims(token, Number(ctx.timestamp.microsSinceUnixEpoch / 1000000n));
    return ctx.withTx(tx => {
      const existing = tx.db.userIdentities.identity.find(tx.sender);
      if (existing) {
        const user = tx.db.users.id.find(existing.userId);
        if (!user || user.status !== 'active') fail('unauthorized');
        return {apiVersion:1,serverTime:now(tx),error:'',payload:json({userId:user.id})};
      }
      const id = uid(tx);
      tx.db.users.insert({id,name:claims.name,avatar:'',status:'active',created:stamp(tx)});
      tx.db.userIdentities.insert({identity:tx.sender,userId:id});
      tx.db.userPreferences.insert({userId:id,vegetarian:false,area:'',smartAlerts:false,version:1});
      tx.db.carts.insert({userId:id,version:1,updated:stamp(tx)});
      tx.db.sellerStats.insert({userId:id,ratingTotal:0,ratingCount:0,completed:0});
      tx.db.notificationPreferences.insert({userId:id,messages:true,pickups:true,discovery:false});
      return {apiVersion:1,serverTime:now(tx),error:'',payload:json({userId:id})};
    });
  } catch {
    return {apiVersion:1,serverTime:Number(ctx.timestamp.microsSinceUnixEpoch/1000n),error:'unauthorized',payload:'{}'};
  }
});

export const completePayment = db.procedure({ attemptId:t.string(), succeeded:t.bool(), reference:t.string() }, Result, (ctx,q)=>ctx.withTx(tx=>{
  simulator(tx,'payment');const p=tx.db.paymentAttempts.id.find(q.attemptId);if(!p)fail('not_found');
  if(p.status==='succeeded' && (!q.succeeded || p.provider!==q.reference))fail('stale_version');
  if(p.status==='succeeded')return {apiVersion:1,serverTime:now(tx),error:'',payload:json({id:p.id})};
  if(p.status!=='pending')fail('invalid_transition');
  const {s,r}=currentStop(tx,p.buyerId,p.stopId);if(r.phase!=='paying')fail('invalid_transition');
  if(!q.succeeded){tx.db.paymentAttempts.id.update({...p,status:'failed',provider:q.reference});changePhase(tx,s,r,'payment');return {apiVersion:1,serverTime:now(tx),error:'',payload:'{}'};}
  const receipt=tx.db.receipts.insert({id:uid(tx),buyerId:p.buyerId,sellerId:p.sellerId,stopId:s.id,paymentId:p.id,paid:p.amount,currency:'USD',completed:stamp(tx),simulation:true,sellerName:tx.db.users.id.find(p.sellerId)!.name});
  let saved=0,grams=0,items=0;
  for(const item of tx.db.pickupStopItems.stopId.filter(s.id)){
    const reservation=checkClaim(tx,item.reservationId),l=listing(tx,item.listingId);
    tx.db.receiptItems.insert({id:uid(tx),receiptId:receipt.id,listingId:l.id,title:l.title,price:reservation.price,retail:l.retail,grams:l.grams,media:mediaURL(tx,l.id),category:l.category});
    saved+=Math.max(0,l.retail-reservation.price);grams+=l.grams;items++;
    tx.db.listings.id.update({...l,status:'sold',version:l.version+1});indexListing(tx,{...l,status:'sold'});
    tx.db.reservations.id.update({...reservation,status:'paid'});tx.db.inventoryClaims.listingId.delete(l.id);tx.db.cartItems.id.delete(`${p.buyerId}:${l.id}`);
  }
  const month=new Date(now(tx)).toISOString().slice(0,7);
  for(const userId of [p.buyerId,p.sellerId]){
    const id=`${userId}:${month}:demo`,m=tx.db.impactMonthly.id.find(id)??{id,userId,month,mode:'demo',items:0,saved:0,grams:0,earnings:0};
    const updated={...m,items:m.items+(userId===p.buyerId?items:0),saved:m.saved+(userId===p.buyerId?saved:0),grams:m.grams+(userId===p.buyerId?grams:0),earnings:m.earnings+(userId===p.sellerId?p.amount:0)};
    if(tx.db.impactMonthly.id.find(id))tx.db.impactMonthly.id.update(updated);else tx.db.impactMonthly.insert(updated);
  }
  const stats=tx.db.sellerStats.userId.find(p.sellerId)!;tx.db.sellerStats.userId.update({...stats,completed:stats.completed+1});
  tx.db.paymentAttempts.id.update({...p,status:'succeeded',provider:q.reference});
  tx.db.pickupStops.id.update({...s,status:'paid',phase:'rescued'});tx.db.pickupRuns.id.update({...r,phase:'rescued',version:r.version+1});bumpCart(tx,p.buyerId);
  return {apiVersion:1,serverTime:now(tx),error:'',payload:json({receiptId:receipt.id})};
}));
export const completeAnalysis=db.procedure({jobId:t.string(),suggestions:t.string()},t.unit(),(ctx,q)=>ctx.withTx(tx=>{
  simulator(tx,'analysis');const job=tx.db.analysisJobs.id.find(q.jobId);if(!job)fail('not_found');
  if(job.status==='completed')return {};JSON.parse(q.suggestions);tx.db.analysisJobs.id.update({...job,status:'completed',provider:'local-simulator',suggestions:q.suggestions});return {};
}));
export const configureLocal = db.procedure({ enabled:t.bool() },t.unit(),(ctx,q)=>ctx.withTx(tx=>{
  owner(tx);const row={id:'runtime',simulation:q.enabled,local:q.enabled};if(tx.db.configuration.id.find('runtime'))tx.db.configuration.id.update(row);else tx.db.configuration.insert(row);return {};
}));
export const authorizeService = db.procedure({ identity:t.string(),role:t.string() },t.unit(),(ctx,q)=>ctx.withTx(tx=>{
  owner(tx);if(!tx.db.configuration.id.find('runtime')?.local||!['payment','analysis'].includes(q.role))fail('unauthorized');
  if(tx.db.servicePrincipals.identity.find(new Identity(q.identity)))tx.db.servicePrincipals.identity.update({...q,identity:new Identity(q.identity)});else tx.db.servicePrincipals.insert({...q,identity:new Identity(q.identity)});return {};
}));
export const bindDemoIdentity = db.procedure({identity:t.string(),userId:t.string()},t.unit(),(ctx,q)=>ctx.withTx(tx=>{
  owner(tx);if(!tx.db.configuration.id.find('runtime')?.local||!tx.db.users.id.find(q.userId))fail('unauthorized');
  const old=tx.db.userIdentities.identity.find(new Identity(q.identity));if(old){if(old.userId!==q.userId)fail('unauthorized');return {};}
  tx.db.userIdentities.insert({...q,identity:new Identity(q.identity)});return {};
}));

import fixtures from './fixtures';
export const seed = db.procedure({ assets:t.string(),count:t.u32() },t.unit(),(ctx,q)=>ctx.withTx(tx=>{
  owner(tx);if(!tx.db.configuration.id.find('runtime')?.local)fail('unauthorized');
  seedCatalog(tx,q.assets,q.count,false);return {};
}));

// Catalog-only cloud provisioning never enables local services or binds demo identities.
export const seedCloudCatalog = db.procedure(t.unit(),ctx=>ctx.withTx(tx=>{
  owner(tx);seedCatalog(tx,'{}',200,true);return {};
}));
function seedCatalog(tx: Ctx, assetJSON: string, count: number, cloud: boolean) {
  const version=cloud?'rescue-cloud-catalog-v1':'rescue-v1';
  if(tx.db.seedVersions.id.find(version))return;
  if(count<200||count>20000)fail('invalid_transition');
  for (const tag of [{id:'vegetarian',label:'Vegetarian',kind:'dietary'},{id:'milk',label:'Milk',kind:'allergen'},{id:'wheat',label:'Wheat',kind:'allergen'}])tx.db.tags.insert(tag);
  const assets=JSON.parse(assetJSON) as Record<string,{hash:string;key:string;width:number;height:number}>;
  const names=['Maya Chen','Alex Rivera','Nina Park','Jordan Reed','Sam Patel','You','Riley Green','Casey Bell','Avery Brooks','Taylor Lane','Morgan Lee','Jamie Kim'];
  const ids=['maya','alex','nina','jordan','sam','demo-buyer','riley','casey','avery','taylor','morgan','jamie'];
  for(let i=0;i<ids.length;i++){
    const id=ids[i];tx.db.users.insert({id,name:names[i],avatar:'',status:'active',created:stamp(tx)});
    tx.db.userPreferences.insert({userId:id,vegetarian:i%2===0,area:'Linden Park',smartAlerts:false,version:1});
    tx.db.carts.insert({userId:id,version:1,updated:stamp(tx)});tx.db.sellerStats.insert({userId:id,ratingTotal:0,ratingCount:0,completed:0});
    tx.db.notificationPreferences.insert({userId:id,messages:true,pickups:true,discovery:false});
    tx.db.referralCodes.insert({code:`RESCUE-${id.toUpperCase()}`,userId:id});
    tx.db.pickupLocations.insert({id:`location-${id}`,sellerId:id,area:id==='nina'?'North Campus':'Linden Park',
      latitude:42.28+(i%4)*0.002,longitude:-83.74+Math.floor(i/4)*0.002,
      exactLatitude:42.2802+(i%4)*0.002,exactLongitude:-83.7402+Math.floor(i/4)*0.002,
      address:`${100+i} Demo Lane (fictional)`,instructions:cloud?'Sample pickup location (fictional)':'Local demo pickup · meet at the front door'});
  }
  for(let i=0;i<count;i++){
    const f=fixtures[i%fixtures.length],id=i<fixtures.length?f.id:`listing-${String(i).padStart(5,'0')}`;
    let sellerId=i<fixtures.length?f.sellerID:ids[i%ids.length];
    if(i>=count-3 && sellerId==='demo-buyer')sellerId='maya';
    const row=tx.db.listings.insert({id,sellerId,title:i<fixtures.length?f.name:`${f.name} · package ${i+1}`,description:cloud?'Sample food package (fictional)':'Local demo food package',
      category:f.category,quantity:f.quantity,price:f.price+(i<fixtures.length?0:i%5*25),retail:f.retail,grams:Math.round(f.weight*453.59237),
      freshness:f.freshness,opened:f.opened,prepared:f.prepared,storage:f.storage,allergens:f.allergens,vegetarian:f.vegetarian,
      purchased:'Today',bestBy:'',status:i===count-1?'archived':i>=count-3?'sold':'published',area:'Linden Park',version:1,created:stamp(tx)-BigInt(i*1000),creationOrder:9007199254740991n-stamp(tx)+BigInt(i*1000),updated:stamp(tx)-BigInt(i*60000)});
    const a=cloud?{hash:`bundled-${f.id}`,key:`bundle:${f.id}`,width:0,height:0}:assets[f.id];if(a){const mediaId=i<fixtures.length?`seed-${f.id}`:`media-${id}`;
      tx.db.mediaAssets.insert({id:mediaId,ownerId:sellerId,key:a.key,hash:a.hash,mime:'image/jpeg',width:a.width,height:a.height,visibility:'public',state:'ready',created:stamp(tx)});
      tx.db.listingMedia.insert({id:`cover-${id}`,listingId:id,mediaId:mediaId,role:'cover',order:0});}
    tx.db.listingPickupWindows.insert({id:`window-${id}`,listingId:id,locationId:`location-${sellerId}`,
      start:stamp(tx)+BigInt(i%7===6?90000000:-3600000),end:stamp(tx)+BigInt(i%7===6?120000000:86400000),timezone:'America/Detroit'});
    tx.db.listingAttestations.insert({id:`attestation-${id}`,listingId:id,version:1,sellerId,safeStorage:true,accurateCondition:true,noSpoilage:true,allergensDeclared:true,confirmed:stamp(tx)});
    if(row.vegetarian)tx.db.listingTags.insert({id:`${id}:vegetarian`,listingId:id,tagId:'vegetarian'});
    if(row.allergens.toLowerCase().includes('milk'))tx.db.listingTags.insert({id:`${id}:milk`,listingId:id,tagId:'milk'});
    indexListing(tx,row);
    if(!cloud && row.status==='sold'){
      const buyerId='demo-buyer',runId=`seed-run-${i}`,stopId=`seed-stop-${i}`,reservationId=`seed-reservation-${i}`,paymentId=`seed-payment-${i}`,receiptId=`seed-receipt-${i}`;
      const completed=stamp(tx)-BigInt((count-i)*86400000);
      tx.db.pickupRuns.insert({id:runId,buyerId,mode:'Fastest',status:'closed',phase:'idle',currentStop:0,version:1,created:completed});
      tx.db.pickupStops.insert({id:stopId,runId,buyerId,sellerId,locationId:`location-${sellerId}`,sequence:0,proposed:completed,windowEnd:completed,status:'paid',phase:'rescued'});
      tx.db.reservations.insert({id:reservationId,listingId:id,buyerId,sellerId,status:'paid',expires:completed,listingVersion:1,price:row.price});
      tx.db.pickupStopItems.insert({id:`seed-stop-item-${i}`,stopId,listingId:id,reservationId});
      tx.db.paymentAttempts.insert({id:paymentId,buyerId,sellerId,stopId,amount:row.price,status:'succeeded',provider:'seed-demo',simulation:true});
      tx.db.receipts.insert({id:receiptId,buyerId,sellerId,stopId,paymentId,paid:row.price,currency:'USD',completed,simulation:true,sellerName:names[ids.indexOf(sellerId)]});
      tx.db.receiptItems.insert({id:`seed-receipt-item-${i}`,receiptId,listingId:id,title:row.title,price:row.price,retail:row.retail,grams:row.grams,media:mediaURL(tx,id),category:row.category});
      const month=new Date(Number(completed)).toISOString().slice(0,7);
      for(const userId of [buyerId,sellerId]){
        const key=`${userId}:${month}:demo`,old=tx.db.impactMonthly.id.find(key)??{id:key,userId,month,mode:'demo',items:0,saved:0,grams:0,earnings:0};
        const summary={...old,items:old.items+(userId===buyerId?1:0),saved:old.saved+(userId===buyerId?Math.max(0,row.retail-row.price):0),grams:old.grams+(userId===buyerId?row.grams:0),earnings:old.earnings+(userId===sellerId?row.price:0)};
        if(tx.db.impactMonthly.id.find(key))tx.db.impactMonthly.id.update(summary);else tx.db.impactMonthly.insert(summary);
      }
    }
  }
  if(!cloud){
  process(tx,'casey',{action:'reserve',operationId:'seed-cart',resourceId:'listing-00035',text:'',version:0,value:0,enabled:false,cursor:''});
  process(tx,'jamie',{action:'draft',operationId:'seed-draft',resourceId:'',text:'',version:0,value:0,enabled:false,cursor:''});
  for(const seller of ['maya','alex']){const c=conversation(tx,'demo-buyer',seller);sendMessage(tx,seller,c.id,'Welcome! This is a persistent local demo conversation.','seed');}
  tx.db.favorites.insert({id:'demo-buyer:straw',userId:'demo-buyer',listingId:'straw'});
  tx.db.follows.insert({id:'demo-buyer:category:Produce',userId:'demo-buyer',kind:'category',target:'Produce'});
  }
  tx.db.seedVersions.insert({id:version,installed:stamp(tx),count});
}

export const simulatorWork = db.procedure(t.string(),ctx=>ctx.withTx(tx=>{
  const role=tx.db.servicePrincipals.identity.find(tx.sender)?.role;
  if(!role)fail('unauthorized');simulator(tx,role);
  return json(role==='payment'?{payments:[...tx.db.paymentAttempts.iter()].filter(p=>p.status==='pending')}:{jobs:[...tx.db.analysisJobs.iter()].filter(j=>j.status==='queued')});
}));
export const maintenance=db.procedure(t.unit(),ctx=>ctx.withTx(tx=>{
  owner(tx);let count=0;for(const task of tx.db.scheduledExpiryTasks.iter())if(task.due<=now(tx)&&count++<100){
    if(expired(tx,task.resourceId))release(tx,task.resourceId,'expired');tx.db.scheduledExpiryTasks.id.delete(task.id);
  }return {};
}));

export const expireClaim=db.reducer({onSchedule:scheduledTasks},{task:scheduledTasks.rowType},(ctx,{task})=>{
  // Scheduler calls as the database identity. Ordinary identities cannot trigger maintenance outcomes.
  if(!ctx.sender.equals(ctx.databaseIdentity))fail('unauthorized');
  if(expired(ctx,task.resourceId))release(ctx,task.resourceId,'expired');
});

// Local owner-only expiry injection for integration tests; cannot acquire or transfer inventory.
export const expireForTest=db.procedure({reservationId:t.string()},t.unit(),(ctx,q)=>ctx.withTx(tx=>{
  owner(tx);if(!tx.db.configuration.id.find('runtime')?.local)fail('unauthorized');
  const r=tx.db.reservations.id.find(q.reservationId);if(!r)fail('not_found');
  if(r.status!=='held')fail('invalid_transition');tx.db.reservations.id.update({...r,expires:stamp(tx)-1n});return {};
}));
