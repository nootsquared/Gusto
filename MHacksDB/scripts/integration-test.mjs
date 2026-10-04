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
assert.equal(seen.size,Number(process.env.RESCUE_SEED_COUNT||200)-3);console.log('PASS: authenticated bootstrap and 200-row pagination');
const invalid=await api((await identity()).token,'bootstrap');assert.equal(invalid.error,'unauthorized');
for(const token of [buyer,other]){
  const sql=await fetch(`${server}/v1/database/${database}/sql`,{method:'POST',headers:{Authorization:`Bearer ${token}`},body:'SELECT * FROM pickup_locations'});assert.notEqual(sql.status,200);
}
const edit=await api(other,'edit',{resourceId:'straw',text:'{}',version:1,operationId:op()});assert.equal(edit.error,'unauthorized');
assert.equal((await api(other,'messages',{resourceId:'demo-buyer:maya'})).error,'unauthorized');
assert.equal((await api(buyer,'detail',{resourceId:'straw'})).data.privateLocation,undefined);
await assert.rejects(()=>call(buyer,'configureLocal',[true]));
console.log('PASS: sender authorization, private SQL, conversation isolation, owner-only configuration');
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
