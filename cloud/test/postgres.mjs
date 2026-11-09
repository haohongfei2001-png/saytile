// Dedicated empty local database only. Run migrations in the same order as Supabase.
import pg from 'pg';import {readFile,readdir} from 'node:fs/promises';import assert from 'node:assert/strict';import {randomUUID} from 'node:crypto';
const url=new URL(process.argv[2]);assert.ok(['127.0.0.1','localhost'].includes(url.hostname));assert.equal(url.pathname,'/saytile_cloud_test');
const pool=new pg.Pool({connectionString:url.href,max:16});const q=(sql,p)=>pool.query(sql,p);
try{
 await q('create role anon; create role authenticated; create role service_role bypassrls; create schema auth; create table auth.users(id uuid primary key)');
 const dir=new URL('../supabase/migrations/',import.meta.url);for(const name of (await readdir(dir)).sort())await q(await readFile(new URL(name,dir),'utf8'));
 const uid=randomUUID(),other=randomUUID();await q('insert into auth.users values ($1),($2)',[uid,other]);
 await q("select public.st_grant($1,350000,now()+interval '1 day','u',true)",[uid]);await q("select public.st_grant($1,350000,now()+interval '1 day','v',true)",[other]);
 await q('update saytile.control set enabled=true, budget_micros=11000000,asr_hold=35000,review_hold=1000000');
 const ids=Array.from({length:12},()=>randomUUID());
 const reserve=id=>q('select public.st_reserve($1,$2,1) lease',[uid,id]);
 const a=await Promise.allSettled(ids.map(reserve)), ok=a.filter(x=>x.status==='fulfilled');assert.equal(ok.length,2);
 assert.ok(a.filter(x=>x.status==='rejected').every(x=>x.reason.message==='rate_limit'));
 const lease=ok[0].value.rows[0].lease;
 const reviews=await Promise.allSettled(Array.from({length:12},()=>q('select public.st_review($1,$2,1)',[uid,lease])));
 assert.equal(reviews.filter(x=>x.status==='fulfilled').length,1);
 assert.ok(reviews.filter(x=>x.status==='rejected').every(x=>x.reason.message==='already_admitted'));
 await q('select public.st_reserve($1,$2,1)',[other,randomUUID()]);
 const sums=(await q('select committed_micros, (select count(*) from saytile.usage) as rows from saytile.control')).rows[0];
 assert.equal(Number(sums.committed_micros),1105000);assert.equal(Number(sums.rows),4);
 console.log(JSON.stringify({status:'PASS',postgres:(await q('show server_version')).rows[0].server_version,parallelConnections:12,admitted:2,rejected:10,duplicateReviewAdmissions:1,secondUserAdmitted:true,globalCommittedMicros:Number(sums.committed_micros)}));
} finally {await pool.end()}
