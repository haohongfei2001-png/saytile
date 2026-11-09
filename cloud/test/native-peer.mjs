// Loopback only. The native peer and Postgres fixture never receive vendor credentials.
import fs from 'node:fs';import {gateway} from '../lib/gateway.mjs';import {Fault,platform} from '../lib/platform.mjs';import {randomUUID} from 'node:crypto';
const root=process.argv[2],uid=randomUUID();
const env={HOSTED_CALLS_ENABLED:'true',QWEN_API_KEY:'fixture',OPENAI_API_KEY:'fixture',QWEN_WORKSPACE_ID:'fixture',QWEN_REGION:'cn-beijing',SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_SECRET_KEY:'fixture',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fixture'};
const ids=new Set(),reviews=new Set();let started=0,ai=0,bytes=0;
const db={...platform(env),async user(h){if(h.authorization!=='Bearer native-fixture')throw new Fault('login_required',401);return uid},
async rpc(fn,b){if(fn==='reserve'){if(ids.has(b.p_recording))throw new Fault('already_admitted',403);ids.add(b.p_recording);return randomUUID()}
if(fn==='review'){const k=b.p_lease+'/'+b.p_seq;if(reviews.has(k))throw new Fault('already_admitted',403);reviews.add(k)}
if(fn==='admitted')return true;if(fn==='account')return {available:true,active:true}}};
const server=gateway({env,db,openASR(_c,id,recv){started++;const send=(event,payload={})=>recv({header:{task_id:id,event},payload});setImmediate(()=>send('task-started'));let n=0;
return {audio(d){bytes+=d.length;if(!n++)send('result-generated',{output:{sentence:{sentence_id:1,sentence_end:false,text:'没有',begin_time:0,current_time:20}}})},
end(){send('result-generated',{output:{sentence:{sentence_id:1,sentence_end:true,text:'没有，五毫克，五毫克。',begin_time:0,end_time:100}}});send('task-finished')},close(){}}},async ask(_c,text,end){ai++;fs.writeFileSync(root+'/counts.json',JSON.stringify({started,ai,bytes}));return {end,uncertain:false,usage:{input_tokens:12,output_tokens:9,request_id:'synthetic'}}}});
server.listen(0,'127.0.0.1',()=>fs.writeFileSync(root+'/port',String(server.address().port)));
