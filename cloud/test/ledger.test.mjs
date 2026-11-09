import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';
const dir=new URL('../supabase/migrations/',import.meta.url);
export async function database(){
 const pg=new PGlite();await pg.exec('create role anon; create role authenticated; create role service_role bypassrls; create schema auth; create table auth.users(id uuid primary key)');
 for(const name of (await readdir(dir)).sort())await pg.exec(await readFile(new URL(name,dir),'utf8'));
 return pg;
}
test('Postgres grants, isolation, concurrent admission, replay, unresolved cost, reconciliation and revocation',async t=>{
 const pg=await database();t.after(()=>pg.close());
 const a=randomUUID(),b=randomUUID(),id=randomUUID();
 await pg.query('insert into auth.users values ($1),($2)',[a,b]);
 const q=async(sql,args=[])=>(await pg.query(sql,args)).rows;
 const reserve=(uid,r)=>q('select public.st_reserve($1,$2,1) l',[uid,r]);
 await pg.exec('set role authenticated');
 await assert.rejects(q('select * from saytile.accounts'),/permission denied/);
 await assert.rejects(q('select public.st_account($1)',[b]),/permission denied/);
 await assert.rejects(q("select public.st_grant($1,1000000,now(),'x',true)",[a]),/permission denied/);
 await pg.exec('set role service_role');
 await assert.rejects(reserve(a,id),/offline/);
 await pg.exec('update saytile.control set enabled=true,budget_micros=4000000,asr_hold=35000,review_hold=1000000');
 await assert.rejects(reserve(a,id),/no_entitlement/);
 for(let i=0;i<2;i++)await q("select public.st_grant($1,105000,now()+interval '1 day','first',true)",[a]);
 const [{l}]=await reserve(a,id);
 await assert.rejects(reserve(a,id),/already_admitted/);
 await reserve(a,randomUUID());await assert.rejects(reserve(a,randomUUID()),/rate_limit/);
 await assert.rejects(q('select public.st_review($1,$2,1)',[b,l]),/no_entitlement/);
 await q('select public.st_review($1,$2,1)',[a,l]);await assert.rejects(q('select public.st_review($1,$2,1)',[a,l]),/already_admitted/);
 await assert.rejects(q("select public.st_reconcile($1,'1',0,'bill1')",[l]),/in_progress/);
 await q("select public.st_settle($1,'1',NULL,NULL,NULL)",[l]);
 assert.equal(Number((await q('select committed_micros n from saytile.control'))[0].n),1070000);
 await q("select public.st_reconcile($1,'1',100,'bill1')",[l]);
 await q("select public.st_reconcile($1,'1',100,'bill1')",[l]);
 assert.equal(Number((await q('select committed_micros n from saytile.control'))[0].n),70100);
 await q("select public.st_grant($1,0,now(),'rev',false)",[a]);
 await q("select public.st_grant($1,35000,now()+interval '1 day','new',true)",[a]);
 await q("select public.st_settle($1,'audio',1000,NULL,NULL)",[l]);
 assert.equal(Number((await q('select public.st_account($1) a',[a]))[0].a.remaining_ms),35000);
 await assert.rejects(q('select public.st_review($1,$2,2)',[a,l]),/no_entitlement/);
 await q("select public.st_reconcile($1,'audio',40000,'bill2')",[l]);
 assert.equal((await q('select enabled from saytile.control'))[0].enabled,false);
});

