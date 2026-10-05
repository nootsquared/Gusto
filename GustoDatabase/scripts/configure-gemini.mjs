import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
const server=(process.env.GUSTO_SERVER || process.env.RESCUE_SERVER) || 'http://127.0.0.1:3098';
const database=(process.env.GUSTO_DATABASE || process.env.RESCUE_DATABASE);
if(!database)throw Error('Set GUSTO_DATABASE to the database you intend to configure.');
const key=readFileSync(new URL('../.gemini-key',import.meta.url),'utf8').trim();
if(key.length<20 || key.length>200)throw Error('Put only your Gemini API key in GustoDatabase/.gemini-key.');
const raw=execFileSync('spacetime',['login','show','--token'],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
const token=raw.match(/eyJ[A-Za-z0-9_.-]+/)?.[0];
if(!token)throw Error('Sign into the SpacetimeDB CLI as the database owner first.');
const response=await fetch(`${server}/v1/database/${database}/call/configure_gemini`,{
  method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
  body:JSON.stringify([key,process.env.GEMINI_MODEL || 'gemini-3.1-flash-lite']),signal:AbortSignal.timeout(15000),
});
if(!response.ok)throw Error(`Configuration failed: HTTP ${response.status}. No key is printed.`);
console.log('Gemini configured on the selected database. The key remains server-side.');
