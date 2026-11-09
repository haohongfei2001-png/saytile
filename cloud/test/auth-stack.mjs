// Only run on the newly-created local Supabase fixture. No production URLs, mailboxes or keys.
import fs from 'node:fs/promises';import pg from 'pg';import {randomUUID} from 'node:crypto';import {once} from 'node:events';import assert from 'node:assert/strict';
import {gateway} from '../lib/gateway.mjs';import {platform} from '../lib/platform.mjs';
const file=process.argv[2];assert.equal(process.env.SAYTILE_EPHEMERAL_STACK,'1');const raw=JSON.parse(await fs.readFile(file,'utf8'));
const info=raw.env||raw.data?.env||raw.result?.env;assert.ok(info);
const loop=s=>{const u=new URL(s);assert.ok(['127.0.0.1','localhost','[::1]'].includes(u.hostname));return u.origin};
const api=loop(info.API_URL),mail=loop(info.MAILPIT_URL||info.INBUCKET_URL),url=new URL(info.DB_URL);assert.ok(['127.0.0.1','localhost','[::1]'].includes(url.hostname));
const pool=new pg.Pool({connectionString:url.href});let server;
try{
 const identity=await pool.query("select to_regnamespace('saytile') is null as empty");assert.equal(identity.rows[0].empty,true,'requires a fresh dedicated stack');
 const folder=new URL('../supabase/migrations/',import.meta.url);for(const f of (await fs.readdir(folder)).sort())await pool.query(await fs.readFile(new URL(f,folder),'utf8'));
 await pool.query("notify pgrst, 'reload schema'");
 const env={SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_PUBLISHABLE_KEY:info.PUBLISHABLE_KEY||info.ANON_KEY,SUPABASE_SECRET_KEY:info.SECRET_KEY||info.SERVICE_ROLE_KEY};
 const db=platform(env,(u,o)=>{assert.equal(new URL(u).origin,env.SUPABASE_URL);return fetch(api+new URL(u).pathname,o)});
 server=gateway({env,db});server.listen(0,'127.0.0.1');await once(server,'listening');const root='http://127.0.0.1:'+server.address().port;
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
 await db.rpc('grant',{p_uid:first.user.id,p_ms:0,p_until:new Date().toISOString(),p_event:'revoke-'+randomUUID(),p_active:false});
 assert.equal((await account(next)).active,false);assert.ok((await auth('logout',{},next.access_token)).ok);
 const rejected=await auth('token?grant_type=refresh_token',{refresh_token:next.refresh_token});assert.ok([400,401,403].includes(rejected.status));
 console.log(JSON.stringify({status:'PASS',scope:'isolated official Supabase Auth, PostgREST, Postgres and Mailpit',confirmedOTPAccounts:2,apiIdentity:true,manualGrant:true,otherAccountIsolated:true,accountRPCPrivate:true,refresh:true,revocation:true,logoutInvalidatesRefresh:true,modelCalls:0}));
}finally{server?.close();await pool.end()}
