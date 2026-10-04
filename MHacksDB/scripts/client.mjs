import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
export const root=fileURLToPath(new URL('../',import.meta.url));
export const server=process.env.RESCUE_SERVER||'http://127.0.0.1:3000';
export const database=process.env.RESCUE_DATABASE||'mhacksdb';
if(!['127.0.0.1','localhost'].includes(new URL(server).hostname))throw Error('Development tools require loopback');
export function ownerToken(){
  const raw=execFileSync('spacetime',['login','show','--token'],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
  const token=raw.match(/eyJ[A-Za-z0-9_.-]+/);if(!token)throw Error('Local database owner token missing');return token[0];
}
export async function identity(){const r=await fetch(`${server}/v1/identity`,{method:'POST'});if(!r.ok)throw Error(`identity ${r.status}`);return r.json();}
export async function call(token,name,args){
  const r=await fetch(`${server}/v1/database/${database}/call/${name.replace(/[A-Z]/g,c=>'_'+c.toLowerCase())}`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(args.map(a=>a && typeof a==='object' && !Array.isArray(a)?Object.fromEntries(Object.entries(a).map(([k,v])=>[k.replace(/[A-Z]/g,c=>'_'+c.toLowerCase()),v])):a)),signal:AbortSignal.timeout(15000)});
  const raw=await r.text();if(!r.ok)throw Error(`${name}: HTTP ${r.status}: ${raw.slice(0,300)}`);
  const wire=JSON.parse(raw);
  // 2.10.2 returns the BSATN JSON product as an array. Strings/unit stay scalar/array.
  if(name==='api'||name==='completePayment'){
    const result=Array.isArray(wire)?{apiVersion:wire[0],serverTime:wire[1],error:wire[2],payload:wire[3]}:{...wire,apiVersion:wire.api_version,serverTime:wire.server_time};
    return {...result,data:JSON.parse(result.payload)};
  }
  return wire;
}
export function request(action,extra={}){return {action,operationId:'',resourceId:'',text:'',version:0,value:0,enabled:false,cursor:'',...extra};}
export async function api(token,action,extra={}){return call(token,'api',[request(action,extra)]);}
export function loadSessions(){return JSON.parse(readFileSync(`${root}.spacetime/sessions-${database}.json`));}
export function saveSessions(value){mkdirSync(`${root}.spacetime`,{recursive:true});writeFileSync(`${root}.spacetime/sessions-${database}.json`,JSON.stringify(value,null,2),{mode:0o600});}
