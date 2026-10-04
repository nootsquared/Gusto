import http from 'node:http';
import {readFileSync,statSync} from 'node:fs';
import {root,loadSessions,api,database} from './client.mjs';
const registry=JSON.parse(readFileSync(`${root}.spacetime/media/registry.json`));
const hashes=new Set(Object.values(registry).map(a=>a.hash));
http.createServer(async(req,res)=>{
  try{
    const url=new URL(req.url,'http://localhost');
    // Explicit development credential distribution: loopback only, never deploy this service.
    if(url.pathname==='/dev/accounts'){
      const sessions=loadSessions();res.setHeader('Content-Type','application/json');res.setHeader('Cache-Control','no-store');
      return res.end(JSON.stringify({database,accounts:sessions.accounts.map(({userId,token})=>({userId,token}))}));
    }
    let hash,variant='detail';
    const publicPath=url.pathname.match(/^\/media\/([a-f0-9]{64})\/(thumbnail|detail)\.jpg$/);
    if(publicPath){hash=publicPath[1];variant=publicPath[2];if(!hashes.has(hash))throw Error('missing');}
    else{
      const privatePath=url.pathname.match(/^\/private\/([a-zA-Z0-9-]+)$/);if(!privatePath)throw Error('missing');
      const token=req.headers.authorization?.replace(/^Bearer /,'');if(!token){res.writeHead(401);return res.end();}
      const r=await api(token,'media',{resourceId:privatePath[1]});if(r.error){res.writeHead(403);return res.end();}hash=r.data.hash;
      if(!hashes.has(hash))throw Error('missing');
      res.setHeader('Cache-Control','private, no-store');
    }
    const path=`${root}.spacetime/media/${hash}/${variant}.jpg`;
    const bytes=readFileSync(path);res.setHeader('Content-Type','image/jpeg');res.setHeader('Content-Length',statSync(path).size);
    if(publicPath)res.setHeader('Cache-Control','public, max-age=31536000, immutable');res.end(bytes);
  }catch{res.writeHead(404);res.end();}
}).listen(8081,'127.0.0.1',()=>console.log(`Local media and debug account provisioning for ${database} on http://127.0.0.1:8081`));
