import { createHash } from 'node:crypto';
import { readFileSync,writeFileSync,mkdirSync,existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { root,database,ownerToken,identity,call,saveSessions,loadSessions } from './client.mjs';
const owner=ownerToken();
await call(owner,'configureLocal',[true]);
const fixture=JSON.parse(readFileSync(`${root}spacetimedb/src/fixtures.ts`,'utf8').replace('export default ','').replace(/;\s*$/,''));
function stripMetadata(bytes){
  if(bytes[0]!==0xff||bytes[1]!==0xd8)throw Error('Expected JPEG');
  const parts=[bytes.subarray(0,2)];let offset=2;
  while(offset<bytes.length){
    if(bytes[offset]!==0xff)throw Error('Invalid JPEG marker');
    const marker=bytes[offset+1];
    if(marker===0xda||marker===0xd9){parts.push(bytes.subarray(offset));break;}
    const length=bytes.readUInt16BE(offset+2),end=offset+2+length;
    if(![0xe1,0xed,0xfe].includes(marker))parts.push(bytes.subarray(offset,end));
    offset=end;
  }
  return Buffer.concat(parts);
}
const assets={};
for(const f of fixture){
  const source=`${root}../Gusto/Resources/Assets.xcassets/${f.id}.imageset/image.jpg`;
  if(!existsSync(source))continue;
  // sips creates sanitized JPEG variants; copies lose embedded GPS metadata.
  const original=readFileSync(source), hash=createHash('sha256').update(original).digest('hex');
  const dir=`${root}.spacetime/media/${hash}`;mkdirSync(dir,{recursive:true});
  for(const [variant,size] of [['detail',1200],['thumbnail',240]]){
    const out=`${dir}/${variant}.jpg`;execFileSync('sips',['-s','format','jpeg','-Z',String(size),source,'--out',out],{stdio:'ignore'});
    writeFileSync(out,stripMetadata(readFileSync(out)));
  }
  const dimensions=execFileSync('sips',['-g','pixelWidth','-g','pixelHeight',`${dir}/detail.jpg`],{encoding:'utf8'});
  assets[f.id]={hash,key:hash,width:Number(dimensions.match(/pixelWidth: (\d+)/)[1]),height:Number(dimensions.match(/pixelHeight: (\d+)/)[1])};
}
writeFileSync(`${root}.spacetime/media/registry.json`,JSON.stringify(assets));
writeFileSync(`${root}.spacetime/media/provenance.json`,readFileSync(`${root}../docs/ASSETS.json`));
await call(owner,'seed',[JSON.stringify(assets),Number((process.env.GUSTO_SEED_COUNT || process.env.RESCUE_SEED_COUNT)||200)]);
let sessions;
try{sessions=loadSessions();}catch{sessions={accounts:[],services:{}};}
for(const userId of ['maya','alex','nina','jordan','sam','demo-buyer','riley','casey','avery','taylor','morgan','jamie']){
  if(sessions.accounts.some(s=>s.userId===userId))continue;
  const s=await identity();await call(owner,'bindDemoIdentity',[s.identity,userId]);sessions.accounts.push({userId,token:s.token,identity:s.identity});saveSessions(sessions);
}
for(const role of ['payment','analysis']){
  if(sessions.services[role])continue;
  const s=await identity();await call(owner,'authorizeService',[s.identity,role]);sessions.services[role]=s;saveSessions(sessions);
}
console.log(`Provisioned ${sessions.accounts.length} separate accounts in local ${database}. Credentials stay in ignored .spacetime storage.`);
