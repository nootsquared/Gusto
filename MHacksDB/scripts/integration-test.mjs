import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { api,call,loadSessions,server,database,identity,ownerToken } from './client.mjs';
const sessions=loadSessions(),account=id=>sessions.accounts.find(a=>a.userId===id).token;
const buyer=account('demo-buyer'),other=account('riley'),maya=account('maya');
const op=()=>randomUUID();
async function good(token,action,extra={}){const r=await api(token,action,extra);assert.equal(r.error,'',`${action}: ${JSON.stringify(r)}`);return r.data;}
const bootstrap=await good(buyer,'bootstrap');assert.equal(bootstrap.user.id,'demo-buyer');
let page=await good(buyer,'feed',{text:'{}'});assert.equal(page.listings.length,30);
assert(page.candidateScans<=500);
const seen=new Set(page.listings.map(l=>l.id));while(page.cursor){page=await good(buyer,'feed',{text:'{}',cursor:page.cursor});assert(page.candidateScans<=500);for(const l of page.listings){assert(!seen.has(l.id));seen.add(l.id);}}
assert.equal(seen.size,Number(process.env.RESCUE_SEED_COUNT||200)-3-bootstrap.ownListings.filter(l=>l.available).length);console.log('PASS: authenticated bootstrap and 200-row pagination');
const invalid=await api((await identity()).token,'bootstrap');assert.equal(invalid.error,'unauthorized');
for(const token of [buyer,other]){
  const sql=await fetch(`${server}/v1/database/${database}/sql`,{method:'POST',headers:{Authorization:`Bearer ${token}`},body:'SELECT * FROM pickup_locations'});assert.notEqual(sql.status,200);
}
const edit=await api(other,'edit',{resourceId:'straw',text:'{}',version:1,operationId:op()});assert.equal(edit.error,'unauthorized');
assert.equal((await api(other,'messages',{resourceId:'demo-buyer:maya'})).error,'unauthorized');
assert.equal((await api(buyer,'detail',{resourceId:'straw'})).data.privateLocation,undefined);
await assert.rejects(()=>call(buyer,'configureLocal',[true]));
console.log('PASS: sender authorization, private SQL, conversation isolation, owner-only configuration');
// Private scans stay account-scoped and only become marketplace listings after explicit review.
const foodID='integration-food-'+op();
const food={name:'Tomato',variety:'Roma',quantity:'3 tomatoes',condition:'Ripe',storage:'Counter',
  photoBase64:'/9j/2Q==',identification:'Manual review',confidence:0,deviceID:'integration-sensor'};
await good(other,'inventory_save',{resourceId:foodID,text:JSON.stringify(food),operationId:op()});
assert((await good(other,'inventory')).items.some(i=>i.id===foodID));
assert(!(await good(buyer,'inventory')).items.some(i=>i.id===foodID));
assert.equal((await api(buyer,'inventory_save',{resourceId:foodID,text:JSON.stringify(food),operationId:op()})).error,'unauthorized');
assert.equal((await api(buyer,'inventory_remove',{resourceId:foodID,operationId:op()})).error,'unauthorized');
assert(!(await good(buyer,'search',{text:JSON.stringify({query:'Roma Tomato'})})).listings.some(l=>l.id===foodID));
const sample={deviceID:'integration-sensor',temperature:22,humidity:56,light:180};
assert.equal((await api(buyer,'sensor_reading',{resourceId:foodID,text:JSON.stringify(sample),operationId:op()})).error,'unauthorized');
await good(other,'sensor_reading',{resourceId:foodID,text:JSON.stringify(sample),operationId:op()});
assert.equal((await good(other,'inventory')).readings.filter(r=>r.itemID===foodID).length,1);
assert(!(await good(buyer,'inventory')).readings.some(r=>r.itemID===foodID));
assert.equal((await api(other,'sensor_reading',{resourceId:foodID,text:JSON.stringify({...sample,humidity:150}),operationId:op()})).error,'invalid_transition');
const listingReview={price:250,allergens:'None known',pickupAddress:'Museum of Art, Ann Arbor',latitude:42.275,longitude:-83.74,
  start:Date.now()+3600000,end:Date.now()+10800000,safeStorage:true,accurateCondition:true,noSpoilage:true,allergensDeclared:true};
assert.equal((await api(other,'inventory_publish',{resourceId:foodID,text:JSON.stringify({...listingReview,safeStorage:false}),operationId:op()})).error,'invalid_transition');
const foodListing=await good(other,'inventory_publish',{resourceId:foodID,text:JSON.stringify(listingReview),operationId:op()});
assert.equal((await good(other,'inventory')).items.find(i=>i.id===foodID).listingID,foodListing.id);
const listedFood=(await good(buyer,'search',{text:JSON.stringify({query:'Roma Tomato'})})).listings.find(l=>l.id===foodListing.id);
assert(listedFood);assert.equal(listedFood.imageURL,'data:image/jpeg;base64,'+food.photoBase64);
assert.equal(listedFood.latitude,listingReview.latitude);
assert.equal(listedFood.longitude,listingReview.longitude);
assert.equal(listedFood.storageConditions.sampleCount,1);
assert.equal(listedFood.storageConditions.temperature,22);
assert.equal(listedFood.storageConditions.humidity,56);
assert(!(await good(other,'search',{text:JSON.stringify({query:'Roma Tomato'})})).listings.some(l=>l.id===foodListing.id));
assert.equal((await api(other,'add_cart',{resourceId:foodListing.id,operationId:op()})).error,'unavailable');
const freshOp=op();
const fresh=await good(buyer,'freshness',{resourceId:foodListing.id,operationId:freshOp});
await good(buyer,'freshness',{resourceId:foodListing.id,operationId:freshOp});
await good(buyer,'freshness',{resourceId:foodListing.id,operationId:op()});
const freshMessages=(await good(other,'messages',{resourceId:'demo-buyer:riley'})).messages.filter(m=>m.text.includes('Fresh Check for Roma Tomato'));
assert.equal(freshMessages.length,1);
assert.equal(freshMessages[0].senderId,'demo-buyer');
assert.equal((await api(other,'freshness',{resourceId:foodListing.id,operationId:op()})).error,'unavailable');
console.log('PASS: exact pickup coordinates, recorded storage snapshot, own listings excluded, Fresh Check seller message and duplicate protection');

assert.equal((await api(other,'inventory_publish',{resourceId:foodID,text:JSON.stringify(listingReview),operationId:op()})).error,'invalid_transition');
await good(other,'inventory_unlist',{resourceId:foodID,operationId:op()});
assert(!(await good(buyer,'search',{text:JSON.stringify({query:'Roma Tomato'})})).listings.some(l=>l.id===foodListing.id));
await good(other,'inventory_remove',{resourceId:foodID,operationId:op()});
assert(!(await good(other,'inventory')).readings.some(r=>r.itemID===foodID));
console.log('PASS: private scan ownership, sensor validation, reviewed listing with real-photo reference, unlist and deletion');

// Saving a cart must not hold inventory or start seller coordination.
for(const token of [buyer,other]){
  await good(token,'add_cart',{resourceId:'straw',operationId:op()});
  await good(token,'add_cart',{resourceId:'straw',operationId:op()});
  const saved=await good(token,'bootstrap');
  assert.equal(saved.cart.filter(id=>id==='straw').length,1);
  assert.equal(saved.reservations.length,0);
  assert.equal(saved.run,null);
}
// Confirmation claims inventory; a competing cart stays saved and cannot partly reserve.
await good(buyer,'release',{resourceId:'straw',operationId:op()});
await good(buyer,'add_cart',{resourceId:'yog',operationId:op()});
await good(buyer,'add_cart',{resourceId:'straw',operationId:op()});
await good(other,'plan',{text:'Fastest',operationId:op()});
assert.equal((await good(other,'bootstrap')).reservations.length,1);
assert.equal((await api(buyer,'plan',{text:'Fastest',operationId:op()})).error,'unavailable');
assert.equal((await good(buyer,'bootstrap')).reservations.length,0);
for(const token of [buyer,other]) await good(token,'release',{resourceId:'straw',operationId:op()});
await good(buyer,'release',{resourceId:'yog',operationId:op()});
console.log('PASS: saved carts have no holds, confirmation reserves, and failed confirmation rolls back');
// Phone origin, explicit reorder, seller-visible requests and repeat-send guards.
for(const id of ['bread','pasta'])await good(buyer,'add_cart',{resourceId:id,operationId:op()});
assert.equal((await api(buyer,'plan',{text:JSON.stringify({latitude:999,longitude:0}),operationId:op()})).error,'invalid_transition');
const origin={latitude:42.29,longitude:-83.73,mode:'Fastest'};
let ordered=await good(buyer,'plan',{text:JSON.stringify(origin),operationId:op()});
assert.equal(ordered.stops.length,2);
const order=ordered.stops.map(s=>s.id).reverse();
ordered=await good(buyer,'reorder_plan',{resourceId:ordered.id,text:JSON.stringify({...origin,order}),operationId:op()});
assert.deepEqual(ordered.stops.map(s=>s.id),order);
await good(buyer,'coordinate',{resourceId:ordered.id,operationId:op()});
const before=(await good(account(ordered.stops[0].seller.id),'messages',{resourceId:[ordered.stops[0].seller.id,'demo-buyer'].sort().join(':')})).messages.length;
await good(buyer,'coordinate',{resourceId:ordered.id,operationId:op()});
assert.equal((await good(account(ordered.stops[0].seller.id),'messages',{resourceId:[ordered.stops[0].seller.id,'demo-buyer'].sort().join(':')})).messages.length,before);
assert.equal((await api(buyer,'reorder_plan',{resourceId:ordered.id,text:JSON.stringify({...origin,order:order.toReversed()}),operationId:op()})).error,'invalid_transition');
for(const stop of ordered.stops){
 const sellerToken=account(stop.seller.id);
 assert((await good(sellerToken,'bootstrap')).pickupRequests.some(r=>r.id===stop.id&&r.buyerId==='demo-buyer'));
 await good(sellerToken,'confirm',{resourceId:stop.id,operationId:op()});
}
assert((await good(buyer,'bootstrap')).run.stops.every(s=>s.status==='confirmed'));
for(const id of ['bread','pasta'])await good(buyer,'release',{resourceId:id,operationId:op()});
console.log('PASS: phone origin, reordered pickup route, seller request controls and duplicate coordination guard');


// Different operation IDs compete for the same inventory claim.
const race=await Promise.all([api(buyer,'reserve',{resourceId:'straw',operationId:op()}),api(other,'reserve',{resourceId:'straw',operationId:op()})]);
assert.equal(race.filter(r=>r.error==='').length,1);assert.equal(race.filter(r=>r.error==='unavailable').length,1);
const winning=race[0].error===''?buyer:other,winningId=race[0].error===''?'demo-buyer':'riley';
const repeated=op();await good(winning,'reserve',{resourceId:'straw',operationId:repeated});await good(winning,'reserve',{resourceId:'straw',operationId:repeated});
assert.equal((await api(winning,'reserve',{resourceId:'yog',operationId:repeated})).error,'stale_version');
assert.equal((await good(winning,'bootstrap')).cart.filter(id=>id==='straw').length,1);
const message=op();await good(buyer,'send',{resourceId:'maya',text:'Persistent integration hello',operationId:message});await good(buyer,'send',{resourceId:'maya',text:'Persistent integration hello',operationId:message});
const messages=await good(maya,'messages',{resourceId:'demo-buyer:maya'});assert.equal(messages.messages.filter(m=>m.operationId===message).length,1);
console.log('PASS: racing reservations and retry deduplication');
let run=await good(winning,'plan',{text:'Fastest',operationId:op()});await good(winning,'coordinate',{resourceId:run.id,operationId:op()});
assert.equal((await good(winning,'bootstrap')).run.stops[0].privateLocation,null);
await good(maya,'confirm',{resourceId:run.stops[0].id,operationId:op()});
let b=await good(winning,'bootstrap');assert(b.run.stops[0].privateLocation.address);assert.equal(b.reservations[0].expires,b.run.stops[0].windowEnd+900000);
await good(winning,'start',{resourceId:run.id,operationId:op()});
assert.equal((await api(winning,'verify',{resourceId:run.stops[0].id,operationId:op()})).error,'invalid_transition');
await good(winning,'arrive',{resourceId:run.stops[0].id,operationId:op()});await good(winning,'announce',{resourceId:run.stops[0].id,operationId:op()});
assert.equal((await api(winning,'handoff',{resourceId:run.stops[0].id,operationId:op()})).error,'unauthorized');
await good(maya,'handoff',{resourceId:run.stops[0].id,operationId:op()});await good(winning,'verify',{resourceId:run.stops[0].id,operationId:op()});
const attempt=await good(winning,'payment',{resourceId:run.stops[0].id,operationId:op()});await assert.rejects(()=>call(winning,'completePayment',[attempt.id,true,'forged']));
await call(sessions.services.payment.token,'completePayment',[attempt.id,true,'demo-test']);await call(sessions.services.payment.token,'completePayment',[attempt.id,true,'demo-test']);
b=await good(winning,'bootstrap');assert.equal(b.receipts.filter(r=>r.paymentId===attempt.id).length,1);assert.equal(b.monthly.reduce((s,m)=>s+m.items,0),winningId==='demo-buyer'?3:1);assert.equal(b.cart.length,0);
await good(winning,'advance',{resourceId:run.stops[0].id,operationId:op()});await good(winning,'finish',{resourceId:run.id,operationId:op()});
console.log('PASS: seller-only confirmation/handoff, privacy unlock, booked expiry, service-only payment and immutable receipt');
const draft=await good(other,'draft',{operationId:op()});assert.equal((await api(buyer,'detail',{resourceId:draft.id})).error,'not_found');
const edited=await good(other,'edit',{resourceId:draft.id,version:draft.version,text:JSON.stringify({title:'New seller oats',price:225,freshness:'Fresh'}),operationId:op()});
await good(other,'attach_demo_media',{resourceId:draft.id,operationId:op()});
assert.equal((await api(other,'publish',{resourceId:draft.id,version:edited.version,text:'{}',operationId:op()})).error,'invalid_transition');
await good(other,'publish',{resourceId:draft.id,version:edited.version,text:JSON.stringify({safeStorage:true,accurateCondition:true,noSpoilage:true,allergensDeclared:true}),operationId:op()});
const found=await good(buyer,'search',{text:JSON.stringify({query:'oats'})});assert(found.listings.some(l=>l.id===draft.id));
console.log('PASS: owned draft, individual attestations, genuine publish and discovery by another account');
console.log(`Integration passed for ${winningId} in isolated local ${database}`);

const hold=await good(other,'reserve',{resourceId:'yog',operationId:op()});
await call(ownerToken(),'expireForTest',[hold.id]);
assert.equal((await api(other,'plan',{operationId:op()})).error,'expired');
await good(buyer,'reserve',{resourceId:'yog',operationId:op()});
await good(buyer,'release',{resourceId:'yog',operationId:op()});
assert.equal((await good(other,'bootstrap')).cart.includes('yog'),false);
console.log('PASS: expired holds fail before scheduled cleanup, and another buyer can claim released inventory');
const sales=await good(maya,'history',{enabled:true});
const soldReceipt=sales.receipts.find(r=>r.paymentId===attempt.id);
await good(maya,'profile',{text:'Changed seller name',operationId:op()});
assert.equal((await good(maya,'history',{enabled:true})).receipts.find(r=>r.id===soldReceipt.id).seller.name,soldReceipt.seller.name);
console.log('PASS: seller profile changes preserve immutable receipt snapshots');

if(Number(process.env.RESCUE_SEED_COUNT||200)>500){
  const bounded=await good(buyer,'search',{text:JSON.stringify({maxPrice:0})});
  assert.equal(bounded.listings.length,0);assert.equal(bounded.candidateScans,500);assert(bounded.cursor);
  const next=await good(buyer,'search',{text:JSON.stringify({maxPrice:0}),cursor:bounded.cursor});
  assert.equal(next.candidateScans,500);assert(next.cursor);
  console.log('PASS: sparse filtered searches continue after 500 indexed candidates without dropping later matches');
}
