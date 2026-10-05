import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {api,request,loadSessions,server,database} from './client.mjs';
const sessions=loadSessions();
const seller=sessions.accounts.find(a=>a.userId==='riley').token;
const buyer=sessions.accounts.find(a=>a.userId==='demo-buyer').token;
const photo=readFileSync(process.env.GEMINI_TEST_PHOTO || '/tmp/gusto-gemini-banana.jpg').toString('base64');
let analysis;
if(process.env.GEMINI_REUSE_ANALYSIS==='1') {
  const inventory=await api(seller,'inventory');
  const saved=inventory.data.items.find(i=>i.identification==='Gemini' && i.name.toLowerCase().includes('banana'));
  assert(saved,'No recorded real Gemini banana analysis found');
  analysis=JSON.parse(saved.analysis);
} else if(process.env.GEMINI_SKIP_NETWORK==='1') {
  analysis={name:'Banana',variety:'',category:'Produce',condition:'Ripe',quantity:'1 banana',storage:'Counter',description:'Ripe banana, reviewed by seller',allergens:'Check label',confidence:0.9,opened:false,vegetarian:true,prepared:false,referenceTemperature:20,idealTemperatureMin:13,idealTemperatureMax:20,idealHumidityMin:50,idealHumidityMax:95,qualityDaysMin:2,qualityDaysMax:4,box:[0,0,1000,1000]};
} else {
  const response=await fetch(`${server}/v1/database/${database}/call/api`,{
    method:'POST',headers:{Authorization:`Bearer ${seller}`,'Content-Type':'application/json'},
    body:JSON.stringify([Object.fromEntries(Object.entries(request('scan_analyze',{text:photo})).map(([k,v])=>[k.replace(/[A-Z]/g,c=>'_'+c.toLowerCase()),v]))]),
    signal:AbortSignal.timeout(60000),
  });
  assert.equal(response.status,200);
  const wire=await response.json();assert.equal(wire[2],'',`Gemini failed: ${wire[2]}`);
  analysis=JSON.parse(wire[3]);assert(analysis.name.toLowerCase().includes('banana'));
  assert.equal(analysis.box.length,4);
}
const id=randomUUID(), operationId=()=>randomUUID();
const good=async(token,action,extra={})=>{const r=await api(token,action,extra);assert.equal(r.error,'',`${action}: ${r.error}`);return r.data;};
const item={...analysis,photoBase64:photo,identification:'Gemini',analysis:JSON.stringify(analysis),deviceID:''};
await good(seller,'inventory_save',{resourceId:id,text:JSON.stringify(item),operationId:operationId()});
assert(!(await good(buyer,'inventory')).items.some(i=>i.id===id));
await good(seller,'inventory_track',{resourceId:id,text:'smoke-sensor',operationId:operationId()});
await good(seller,'sensor_reading',{resourceId:id,text:JSON.stringify({deviceID:'smoke-sensor',temperature:24,humidity:60,light:500,lightUnit:'raw'}),operationId:operationId()});
assert.equal((await good(seller,'inventory')).readings.find(r=>r.itemID===id).lightUnit,'raw');
const otherTrack=await api(buyer,'inventory_track',{resourceId:id,text:'other',operationId:operationId()});assert.equal(otherTrack.error,'unauthorized');
const published=await good(seller,'inventory_publish',{resourceId:id,text:JSON.stringify({price:150,allergens:'Check label',pickupAddress:'Demo pickup, Ann Arbor',latitude:42.28,longitude:-83.74,start:Date.now()+3600000,end:Date.now()+7200000,safeStorage:true,accurateCondition:true,noSpoilage:true,allergensDeclared:true}),operationId:operationId()});
const results=await good(buyer,'search',{text:JSON.stringify({query:'banana',latitude:42.28,longitude:-83.74,distance:3})});
assert(results.listings.some(l=>l.id===published.id));
const detail=await good(buyer,'detail',{resourceId:published.id});assert(detail.listing.imageURL.startsWith('data:image/jpeg;base64,'));
await good(buyer,'send',{resourceId:'riley',text:'Hi! Is this banana available?',operationId:operationId()});
assert((await good(seller,'messages',{resourceId:'demo-buyer:riley'})).messages.some(m=>m.text.includes('banana available')));
await good(seller,'inventory_track',{resourceId:id,text:'',operationId:operationId()});
await good(seller,'inventory_unlist',{resourceId:id,operationId:operationId()});
await good(seller,'inventory_remove',{resourceId:id,operationId:operationId()});
console.log(`PASS: ${process.env.GEMINI_SKIP_NETWORK==='1'?'fixture analysis (Gemini network skipped)':process.env.GEMINI_REUSE_ANALYSIS==='1'?'recorded real Gemini photo analysis':'live Gemini photo analysis'}, private save, raw BLE history, owner-only tracking, second-account discovery, photo and chat.`);
console.log(`Identified ${analysis.name}; visible condition ${analysis.condition}; crop box ${analysis.box.join(',')}.`);
