// Only run on the newly-created local Supabase fixture. No production URLs, mailboxes or keys.
import fs from 'node:fs/promises';import os from 'node:os';import path from 'node:path';import {spawn} from 'node:child_process';import WebSocket from 'ws';import pg from 'pg';import {randomUUID} from 'node:crypto';import {once} from 'node:events';import assert from 'node:assert/strict';
import {gateway} from '../lib/gateway.mjs';import {platform} from '../lib/platform.mjs';
const file=process.argv[2];assert.equal(process.env.SAYTILE_EPHEMERAL_STACK,'1');const raw=JSON.parse(await fs.readFile(file,'utf8'));
const info=raw.env||raw.data?.env||raw.result?.env;assert.ok(info);
const loop=s=>{const u=new URL(s);assert.ok(['127.0.0.1','localhost','[::1]'].includes(u.hostname));return u.origin};
const api=loop(info.API_URL),mail=loop(info.MAILPIT_URL||info.INBUCKET_URL),url=new URL(info.DB_URL);assert.ok(['127.0.0.1','localhost','[::1]'].includes(url.hostname));
const pool=new pg.Pool({connectionString:url.href});let server;
try{
 const identity=await pool.query("select to_regnamespace('saytile') is null as empty");if(!identity.rows[0].empty){assert.equal(process.argv[3],'--reuse-own-fixture');assert.ok(path.resolve(file).startsWith('/tmp/saytile-cloud-gotrue.'));
  const existing=await pool.query("select bool_and(email like 'saytile-%@example.invalid') owned from auth.users");assert.equal(existing.rows[0].owned,true)}
 const folder=new URL('../supabase/migrations/',import.meta.url);if(identity.rows[0].empty)for(const f of (await fs.readdir(folder)).sort())await pool.query(await fs.readFile(new URL(f,folder),'utf8'));
 await pool.query("notify pgrst, 'reload schema'");
 const env={SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_PUBLISHABLE_KEY:info.PUBLISHABLE_KEY||info.ANON_KEY,SUPABASE_SECRET_KEY:info.SECRET_KEY||info.SERVICE_ROLE_KEY};
 const trace=[];const db=platform(env,async(u,o)=>{assert.equal(new URL(u).origin,env.SUPABASE_URL);const r=await fetch(api+new URL(u).pathname,o);trace.push([new URL(u).pathname,r.status,r.ok?null:(await r.clone().json()).code]);return r});
 Object.assign(env,{HOSTED_CALLS_ENABLED:'true',QWEN_API_KEY:'fixture',OPENAI_API_KEY:'fixture',QWEN_WORKSPACE_ID:'fixture',QWEN_REGION:'cn-beijing'});
 let asrCalls=0,reviewCalls=0,pcm=0;
 server=gateway({env,db,openASR(_config,id,emit){asrCalls++;const send=(event,payload={})=>emit({header:{task_id:id,event},payload});setImmediate(()=>send('task-started'));
 return {audio(d){pcm+=d.length},end(){send('result-generated',{output:{sentence:{sentence_id:1,sentence_end:true,text:'没有，五毫克，五毫克。',begin_time:0,end_time:100}}});send('task-finished')},close(){}}},async ask(_c,text,end){reviewCalls++;return {end,uncertain:false,usage:{input_tokens:5,output_tokens:6}}}});server.listen(0,'127.0.0.1');await once(server,'listening');const root='http://127.0.0.1:'+server.address().port;
 const auth=(path,body,jwt)=>fetch(api+'/auth/v1/'+path,{method:'POST',headers:{apikey:env.SUPABASE_PUBLISHABLE_KEY,...(jwt?{authorization:'Bearer '+jwt}:{}),'content-type':'application/json'},body:JSON.stringify(body)});
 async function login(){
   const email='saytile-'+randomUUID()+'@example.invalid';assert.equal((await auth('otp',{email})).status,200);
   let code;
   for(let i=0;i<25&&!code;i++){const inbox=await (await fetch(mail+'/api/v1/messages')).json();
     const row=inbox.messages?.find(m=>m.To.some(t=>t.Address===email));
     if(row){const m=await(await fetch(mail+'/api/v1/message/'+row.ID)).json();code=(m.Text+' '+m.HTML).match(/Saytile fixture:\s*(\d{6,10})/i)?.[1]}
     if(!code)await new Promise(r=>setTimeout(r,200));
   }
   assert.ok(code,'isolated local OTP email not received');const v=await auth('verify',{email,token:code,type:'email'});assert.equal(v.status,200);
   const a=await v.json();assert.ok(a.access_token&&a.refresh_token);return a;
 }
 const first=await login(), other=await login(),account=async a=>{const r=await fetch(root+'/v1/account',{headers:{authorization:'Bearer '+a.access_token}});assert.equal(r.status,200);return r.json()};
 assert.equal((await account(first)).active,false);await db.rpc('grant',{p_uid:first.user.id,p_ms:70000,p_until:new Date(Date.now()+3600000).toISOString(),p_event:'fixture-'+randomUUID(),p_active:true});
 assert.equal((await account(first)).remaining_ms,70000);assert.equal((await account(other)).active,false);
 const denied=await fetch(api+'/rest/v1/rpc/st_account',{method:'POST',headers:{apikey:env.SUPABASE_PUBLISHABLE_KEY,authorization:'Bearer '+other.access_token,'content-type':'application/json'},body:JSON.stringify({p_uid:first.user.id})});assert.ok([401,403,404].includes(denied.status));
 const rotated=await auth('token?grant_type=refresh_token',{refresh_token:first.refresh_token});assert.equal(rotated.status,200);const next=await rotated.json();assert.equal((await account(next)).active,true);
 await pool.query('update saytile.control set enabled=true,asr_hold=35000,review_hold=1000000,budget_micros=100000000,user_day_micros=10000000');
 const headers=a=>({authorization:'Bearer '+a.access_token,'x-saytile-recording':randomUUID(),'x-saytile-epoch':'1','x-saytile-consent':'zh-v1'});
 const unpaid=new WebSocket(root.replace('http','ws')+'/v1/stream',{headers:headers(other)});await once(unpaid,'error');assert.equal(asrCalls,0);
 if(process.env.SAYTILE_TEST_NATIVE_PROBE){
   const dir=await fs.mkdtemp(path.join(os.tmpdir(),'saytile-auth-client-'));
   try{const child=spawn(process.env.SAYTILE_TEST_NATIVE_PROBE,[dir,String(server.address().port),'--isolated-auth-session'],{stdio:['pipe','pipe','pipe']});
    let logs='';child.stdout.on('data',d=>logs+=d);child.stderr.on('data',d=>logs+=d);
    const done=once(child,'exit');child.stdin.end(next.access_token+'\n');const [code]=await done;if(code!==0){
      const ledger=await pool.query("select ended,milliseconds,op,settled from saytile.sessions join saytile.usage using(lease) where uid=$1",[first.user.id]);
      console.error(JSON.stringify({trace,asrCalls,reviewCalls,pcm,ledger:ledger.rows,fixtureType:logs.match(/(?:ProviderFailure|CloudCredentialError)[a-zA-Z0-9().-]*/)?.[0],fixtureError:logs.match(/(?:top level: |Fatal error: )([^\n]{1,145})/)?.[1]?.replace(/[a-zA-Z0-9_.-]{28,}/g,'[redacted]')}));
    }assert.equal(code,0,'native authenticated fixture');
    assert.equal(asrCalls,1);assert.ok(reviewCalls>=1);assert.equal(pcm,3200);
   }finally{await fs.rm(dir,{recursive:true,force:true})}
 }
 const streamBeforeLogout=new WebSocket(root.replace('http','ws')+'/v1/stream',{headers:headers(next)});
 await once(streamBeforeLogout,'message');const closed=once(streamBeforeLogout,'close');
 assert.ok((await auth('logout',{},next.access_token)).ok);
 const deadline=AbortSignal.timeout(8500);
 try {const [code]=await Promise.race([closed,new Promise((_,reject)=>deadline.addEventListener('abort',()=>reject(Error('invalidated session still streams')), {once:true}))]);assert.equal(code,1008)}
 finally{streamBeforeLogout.terminate()}
 await db.rpc('grant',{p_uid:first.user.id,p_ms:0,p_until:new Date().toISOString(),p_event:'revoke-'+randomUUID(),p_active:false});
 assert.equal((await db.rpc('account',{p_uid:first.user.id})).active,false);
 const priorAccess=await fetch(root+'/v1/account',{headers:{authorization:'Bearer '+next.access_token}});
 assert.equal(priorAccess.status,401);
 const rejected=await auth('token?grant_type=refresh_token',{refresh_token:next.refresh_token});assert.ok([400,401,403].includes(rejected.status));
 console.log(JSON.stringify({status:'PASS',scope:'isolated official Supabase Auth, PostgREST, Postgres and Mailpit',confirmedOTPAccounts:2,apiIdentity:true,manualGrant:true,otherAccountIsolated:true,accountRPCPrivate:true,refresh:true,revocation:true,logoutInvalidatesRefresh:true,postLogoutAccountHTTP:priorAccess.status,realModelCalls:0,liveRevokedStreamClosed:true,nativeMockASR:asrCalls-1,nativeMockGPT:reviewCalls,unpaidProviderAdmissions:0}));
}finally{server?.close();await pool.end()}
