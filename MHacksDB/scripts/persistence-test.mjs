import assert from 'node:assert/strict';
import {writeFileSync,readFileSync} from 'node:fs';
import {api,root,database,loadSessions} from './client.mjs';
const session=loadSessions().accounts.find(a=>a.userId==='demo-buyer');
const response=await api(session.token,'bootstrap');assert.equal(response.error,'');
const value={user:response.data.user,receiptIDs:response.data.receipts.map(r=>r.id).sort(),monthly:response.data.monthly};
const file=`${root}.spacetime/persistence-${database}.json`;
if(process.argv.includes('--save'))writeFileSync(file,JSON.stringify(value));
else {
  assert.deepEqual(value,JSON.parse(readFileSync(file)));
  const first=await api(session.token,'draft',{operationId:crypto.randomUUID()}),second=await api(session.token,'draft',{operationId:crypto.randomUUID()});
  assert.equal(first.error,'');assert.equal(second.error,'');assert.notEqual(first.data.id,second.data.id);
  console.log('PASS: authoritative profile, receipts and impact survived republish/restart; new writes retain unique IDs');
}
