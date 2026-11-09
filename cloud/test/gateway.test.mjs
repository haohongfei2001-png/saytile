import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {randomUUID} from 'node:crypto';
import WebSocket from 'ws';
import Stripe from 'stripe';
import {gateway} from '../lib/gateway.mjs';
import {platform,Fault} from '../lib/platform.mjs';
import {payments} from '../lib/payments.mjs';
test('loopback PCM → paired Qwen events → authenticated evidence → one review; snapshot/replay protected',async t=>{
 const uid=randomUUID(),other=randomUUID(),id=randomUUID(),lease=randomUUID(),candidateID=randomUUID();
 const env={HOSTED_CALLS_ENABLED:'true',QWEN_API_KEY:'fixture',OPENAI_API_KEY:'fixture',QWEN_WORKSPACE_ID:'fixture',QWEN_REGION:'cn-beijing',SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_SECRET_KEY:'fixture',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fixture'};
 let used=false,reviewed=false,asrs=0,ais=0,bytes=0;const settled=[];
 const db={...platform(env),async user(h){if(h.authorization==='Bearer fixture')return uid;if(h.authorization==='Bearer other')return other;throw new Fault('login_required',401)},
 async rpc(fn,b){if(fn==='account')return {active:true,available:true};if(fn==='reserve'){if(b.p_uid!==uid||used)throw new Fault('denied',403);used=true;return lease}if(fn==='review'){if(reviewed)throw new Fault('already_admitted',403);reviewed=true}
 if(fn==='settle')settled.push(b);}};
 const phrase='我没有说五毫克，五毫克。';
 const server=gateway({env,db,openASR(_c,r,emit){asrs++;const ev=(event,payload={})=>emit({header:{task_id:r,event},payload});setImmediate(()=>ev('task-started'));
 return {audio(d){bytes+=d.length;ev('result-generated',{output:{sentence:{sentence_id:1,text:phrase,sentence_end:true,begin_time:0,end_time:20}}})},end(){ev('task-finished')},close(){}}},async ask(_c,s,n){assert.equal(s,phrase);ais++;return {end:n,uncertain:false,usage:{input_tokens:11,output_tokens:12}}}});
 server.listen(0,'127.0.0.1');await once(server,'listening');t.after(()=>server.close());
 const host='127.0.0.1:'+server.address().port, path='ws://'+host+'/v1/stream', headers={authorization:'Bearer fixture','x-saytile-recording':id,'x-saytile-epoch':'1','x-saytile-consent':'zh-v1'};
 async function denied(h){const ws=new WebSocket(path,{headers:h});await once(ws,'error')}
 await denied({...headers,authorization:'Bearer other'});await denied({...headers,authorization:''});assert.equal(asrs,0);
 const ws=new WebSocket(path,{headers});const events=[];
 const done=new Promise((resolve,reject)=>{ws.on('error',reject);ws.on('message',raw=>{const e=JSON.parse(raw);events.push(e);if(e.event.header.event==='task-started'){ws.send(Buffer.alloc(644));ws.send('eos')}});ws.once('close',resolve)});
 assert.equal(await done,1000);assert.equal(bytes,640);assert.equal(events.length,3);assert.equal(asrs,1);
 await denied(headers);assert.equal(asrs,1);
 const post=(text,auth='fixture')=>fetch('http://'+host+'/v1/review',{method:'POST',headers:{authorization:'Bearer '+auth},body:JSON.stringify({text,proof:events[2].proof,candidateID})});
 assert.equal((await post(phrase,'other')).status,403);assert.equal((await post('改变')).status,403);assert.equal(ais,0);
 const reply=await (await post(phrase)).json();assert.equal(reply.decision.selections[0].utf16End,phrase.length);assert.equal(reply.decision.selections[0].candidateID,candidateID);
 assert.equal((await post(phrase)).status,403);assert.equal(ais,1);assert.equal(settled.length,2);assert.ok(settled.every(s=>s.p_actual===null));
});
test('Stripe signed test invoice routes to server-defined plan; no Stripe network call',async()=>{
 const env={BILLING_ENABLED:'true',PUBLIC_ORIGIN:'https://example.invalid',STRIPE_SECRET_KEY:'sk_test_fixture',STRIPE_WEBHOOK_SECRET:'fixture',STRIPE_PRICE_ID:'fixture_plan',STRIPE_PERIOD_MS:'350000'};
 const entries=[];let status='active';const p=payments(env,{rpc:(...args)=>entries.push(args)},async()=>({customer:'cus_fixture',status,items:{data:[{price:{id:'fixture_plan'}}]}}));
 const payload=JSON.stringify({id:'evt_fixture',type:'invoice.paid',livemode:false,data:{object:{id:'in_fixture',customer:'cus_fixture',status:'paid',amount_paid:100,parent:{subscription_details:{subscription:'sub_fixture'}},lines:{data:[{pricing:{price_details:{price:'fixture_plan'}},quantity:1,amount:100,period:{end:2000000000}}]}}}});
 await assert.rejects(p.webhook(Buffer.from(payload),'invalid'));assert.equal(entries.length,0);
 const sig=Stripe.webhooks.generateTestHeaderString({payload,secret:'fixture'});await p.webhook(Buffer.from(payload),sig);assert.equal(entries[0][1].p_ms,350000);status='canceled';await p.webhook(Buffer.from(payload),sig);assert.equal(entries.length,1);
});
