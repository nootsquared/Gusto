import {api,call,loadSessions} from './client.mjs';
import {randomUUID} from 'node:crypto';
const sessions=loadSessions();
async function act(token,action,extra){const r=await api(token,action,{operationId:randomUUID(),...extra});if(r.error)console.log(`${action}: ${r.error}`);}
async function tick(){
  for(const seller of sessions.accounts){
    const state=await api(seller.token,'seller_activity');if(state.error)continue;
    for(const stop of state.data.stops){
      if(stop.status==='waiting')await act(seller.token,'confirm',{resourceId:stop.id});
      if(stop.phase==='waiting')await act(seller.token,'handoff',{resourceId:stop.id});
    }
    for(const f of state.data.freshness.filter(f=>f.status==='pending'))await act(seller.token,'respond_freshness',{resourceId:f.id});
  }
  const payments=JSON.parse(await call(sessions.services.payment.token,'simulatorWork',[]));
  for(const p of payments.payments)await call(sessions.services.payment.token,'completePayment',[p.id,true,`local-demo:${p.id}`]);
  const jobs=JSON.parse(await call(sessions.services.analysis.token,'simulatorWork',[]));
  for(const j of jobs.jobs)await call(sessions.services.analysis.token,'completeAnalysis',[j.id,JSON.stringify({title:'Maple Granola',category:'Breakfast',freshness:'Fresh',simulation:true})]);
}
console.log('Explicit local simulator running; seller and service credentials are separate from buyers.');
while(true){try{await tick();}catch(error){console.log(error.message);}await new Promise(r=>setTimeout(r,1500));}
