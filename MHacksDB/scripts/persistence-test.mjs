import assert from 'node:assert/strict';
import {writeFileSync,readFileSync} from 'node:fs';
import {api,root,database,loadSessions} from './client.mjs';
const session=loadSessions().accounts.find(a=>a.userId==='demo-buyer');
if(process.argv.includes('--save')) {
  const saved=await api(session.token,'inventory_save',{resourceId:'persistent-scan',operationId:crypto.randomUUID(),text:JSON.stringify({
    name:'Tomato',variety:'Roma',quantity:'2 tomatoes',condition:'Ripe',storage:'Counter',photoBase64:'/9j/2Q==',
    identification:'Manual review',confidence:0,deviceID:'persistent-sensor'})});assert.equal(saved.error,'');
  const reading=await api(session.token,'sensor_reading',{resourceId:'persistent-scan',operationId:crypto.randomUUID(),
    text:JSON.stringify({deviceID:'persistent-sensor',temperature:21,humidity:60,light:100})});assert.equal(reading.error,'');
}
const response=await api(session.token,'bootstrap');assert.equal(response.error,'');
const inventory=await api(session.token,'inventory');assert.equal(inventory.error,'');
const value={user:response.data.user,receiptIDs:response.data.receipts.map(r=>r.id).sort(),monthly:response.data.monthly,inventory:inventory.data};
const file=`${root}.spacetime/persistence-${database}.json`;
if(process.argv.includes('--save'))writeFileSync(file,JSON.stringify(value));
else {
  assert.deepEqual(value,JSON.parse(readFileSync(file)));
  const first=await api(session.token,'draft',{operationId:crypto.randomUUID()}),second=await api(session.token,'draft',{operationId:crypto.randomUUID()});
  assert.equal(first.error,'');assert.equal(second.error,'');assert.notEqual(first.data.id,second.data.id);
  console.log('PASS: authoritative profile, private scan photos, sensor samples, receipts and impact survived republish/restart; new writes retain unique IDs');
}
