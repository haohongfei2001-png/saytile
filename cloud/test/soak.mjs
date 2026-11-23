// Paced local transport/ledger soak. Timings are for simulated providers, never product ASR latency.
import {gateway} from '../lib/gateway.mjs';import {platform,Fault} from '../lib/platform.mjs';import {PGlite} from '@electric-sql/pglite';import WebSocket from 'ws';
import {randomUUID} from 'node:crypto';import {once} from 'node:events';import {readFile,readdir} from 'node:fs/promises';import assert from 'node:assert/strict';
const minutes=Number(process.argv[2]||20);assert.ok(minutes>=1&&minutes<=30);
const db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key)');
const dir=new URL('../supabase/migrations/',import.meta.url);for(const file of (await readdir(dir)).sort())await db.exec(await readFile(new URL(file,dir),'utf8'));
const users=[randomUUID(),randomUUID()];for(const u of users){await db.query('insert into auth.users values($1)',[u]);await db.query("select public.st_grant($1,3000000,now()+interval '1 day',$2,true)",[u,u])}
await db.exec('update saytile.control set enabled=true,user_day_micros=1000000000,budget_micros=1000000000,asr_hold=35000,review_hold=1000000');
const env={HOSTED_CALLS_ENABLED:'true',QWEN_API_KEY:'fixture',OPENAI_API_KEY:'fixture',QWEN_WORKSPACE_ID:'fixture',QWEN_REGION:'cn-beijing',SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_SECRET_KEY:'fixture',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fixture'};
const peer={...platform(env),async user(h){const uid=h.authorization?.slice(7);if(!users.includes(uid))throw new Fault('login_required',401);return uid},
 async rpc(name,args){const a=Object.keys(args);const q='select public.st_'+name+'('+a.map((k,i)=>k+'=> $'+(i+1)).join(',')+') value';return (await db.query(q,Object.values(args))).rows[0].value}};
const sample='没有五毫克。';let bytes=0,asrs=0,ais=0,dropped=0,segments=0;const first=[],ends=[];
const srv=gateway({env,db:peer,openASR(_config,id,emit){asrs++;let n=0;const ev=(event,payload={})=>emit({header:{task_id:id,event},payload});setImmediate(()=>ev('task-started'));
return {audio(d){bytes+=d.length;if(++n===1)ev('result-generated',{output:{sentence:{sentence_id:1,text:'没',sentence_end:false,begin_time:0,current_time:100}}})},
end(){ev('result-generated',{output:{sentence:{sentence_id:1,text:sample,sentence_end:true,begin_time:0,end_time:n*100}}});ev('task-finished')},close(){}}},async ask(c,s,end){ais++;return {end,uncertain:false,usage:{input_tokens:7,output_tokens:3}}}});
srv.listen(0,'127.0.0.1');await once(srv,'listening');const host='127.0.0.1:'+srv.address().port;
async function segment(uid,drop){
 const t=performance.now(),id=randomUUID(),w=new WebSocket('ws://'+host+'/v1/stream',{headers:{authorization:'Bearer '+uid,'x-saytile-recording':id,'x-saytile-consent':'zh-v1','x-saytile-epoch':'1'}});
 let n=0,interval,proof,started=false,eosAt;
 const closed=once(w,'close');w.on('message',raw=>{const msg=JSON.parse(raw.toString());const e=msg.event.header.event;
 if(e==='task-started')interval=setInterval(()=>{if(drop&&n===25){clearInterval(interval);w.terminate();return}
 if(n===200){clearInterval(interval);eosAt=performance.now();w.send('eos');return}const b=Buffer.alloc(3204,0x21);b.writeUInt32BE(n++);w.send(b)},100);
 if(e==='result-generated'&&!started){first.push(performance.now()-t);started=true}if(e==='task-finished')proof=msg.proof});
 const [code]=await closed;clearInterval(interval);if(drop){assert.equal(code,1006);dropped++;return}assert.equal(code,1000);assert.ok(proof);
 const r=await fetch('http://'+host+'/v1/review',{method:'POST',headers:{authorization:'Bearer '+uid},body:JSON.stringify({candidateID:randomUUID(),proof,text:sample})});
 assert.equal(r.status,200);assert.equal((await r.json()).decision.selections[0].utf16End,sample.length);ends.push(performance.now()-eosAt);segments++;
}
const start=Date.now();let wave=0;try{
 while(Date.now()-start<minutes*60000){await Promise.all(users.map((u,i)=>segment(u,wave%13===6&&i===0)));wave++}
 const count=await db.query('select count(*)::int n from saytile.usage where not settled');
 assert.equal(count.rows[0].n,0);assert.equal(asrs,segments+dropped);assert.equal(ais,segments);
 const stats=a=>{a.sort((x,y)=>x-y);return {p50:Math.round(a[Math.floor(a.length*.5)]),p95:Math.round(a[Math.floor(a.length*.95)])}};
 console.log(JSON.stringify({status:'PASS',scope:'paced synthetic localhost only',durationSeconds:(Date.now()-start)/1000,accounts:2,completedSegments:segments,deliberateDisconnects:dropped,asrs,ais,pcmBytes:bytes,unsettled:0,firstLocalEventMS:stats(first),eosToLocalReviewMS:stats(ends)}));
}finally{srv.close();await db.close()}
