begin;
create schema saytile;
revoke all on schema saytile from public, anon, authenticated;
grant usage on schema saytile to service_role;

create table saytile.control (
 singleton boolean primary key default true check(singleton), enabled boolean not null default false,
 user_day_micros bigint not null default 0 check(user_day_micros>=0),
 budget_micros bigint not null default 0 check(budget_micros>=0),
 committed_micros bigint not null default 0 check(committed_micros>=0),
 asr_hold bigint not null default 0 check(asr_hold>=0), review_hold bigint not null default 0 check(review_hold>=0)
);
insert into saytile.control(singleton) values(true);
create table saytile.accounts (
 uid uuid primary key references auth.users(id) on delete cascade,
 remaining_ms bigint not null default 0 check(remaining_ms>=0), valid_until timestamptz not null default now(),
 grant_generation bigint not null default 0, billing_hold boolean not null default false, active boolean not null default false, customer text unique, subscription text, paid_until timestamptz
);
create table saytile.sessions (
 uid uuid not null references saytile.accounts(uid) on delete cascade, recording uuid not null,
 grant_generation bigint not null, epoch bigint not null check(epoch>=0), lease uuid not null unique default gen_random_uuid(), created_at timestamptz not null default now(),
 expires timestamptz not null default now()+interval '150 seconds', ended boolean not null default false,
 milliseconds integer not null default 35000, primary key(uid,recording)
);
create index on saytile.sessions(uid,created_at);
create table saytile.usage (
 lease uuid not null references saytile.sessions(lease) on delete cascade, op text not null,
 reserved bigint not null, actual_micros bigint, units jsonb, settled boolean not null default false,
 created_at timestamptz not null default now(), primary key(lease,op)
);
create table saytile.audit (
 id bigint generated always as identity primary key, uid uuid, external_id text unique,
 action text not null, created_at timestamptz not null default now()
);
alter table saytile.control enable row level security;
alter table saytile.accounts enable row level security;
alter table saytile.sessions enable row level security;
alter table saytile.usage enable row level security;
alter table saytile.audit enable row level security;
grant select,insert,update on all tables in schema saytile to service_role;
grant usage,select on all sequences in schema saytile to service_role;

create function public.st_account(p_uid uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('active', coalesce(a.active and not a.billing_hold and a.valid_until>now(),false), 'remaining_ms',coalesce(a.remaining_ms,0),
 'valid_until',a.valid_until,'plan',case when a.active then '中文语音' else null end,'available',c.enabled)
 from saytile.control c left join saytile.accounts a on a.uid=p_uid
$$;

-- Operational role calls this directly. No administrative endpoint on the public gateway.
create function public.st_grant(p_uid uuid,p_ms bigint,p_until timestamptz,p_event text,p_active boolean) returns void language plpgsql security invoker set search_path='' as $$
begin
 if p_ms<0 or p_event is null or p_until is null then raise exception 'invalid_grant'; end if;
 insert into saytile.audit(uid,external_id,action) values(p_uid,p_event,case when p_active then 'grant' else 'revoke' end) on conflict(external_id) do nothing;
 if not found then return; end if;
 insert into saytile.accounts(uid,remaining_ms,valid_until,active) values(p_uid,p_ms,p_until,p_active)
 on conflict(uid) do update set remaining_ms=case when excluded.active then saytile.accounts.remaining_ms+excluded.remaining_ms else 0 end,
 grant_generation=saytile.accounts.grant_generation+case when excluded.active then 0 else 1 end,
 valid_until=case when excluded.active then greatest(saytile.accounts.valid_until,excluded.valid_until) else excluded.valid_until end,active=excluded.active;
end $$;

-- Evaluated while the same global reservation row is locked. Unknown charges count at the full hold.
create index usage_window on saytile.usage(created_at);
create function saytile.within_daily(p_uid uuid,p_extra bigint,p_limit bigint) returns boolean language sql stable security invoker set search_path='' as $$
 select coalesce(sum(coalesce(u.actual_micros,u.reserved)),0)+p_extra<=p_limit
 from saytile.usage u join saytile.sessions s using(lease) where s.uid=p_uid and u.created_at>now()-interval '24 hours'
$$;
revoke all on function saytile.within_daily(uuid,bigint,bigint) from public, anon,authenticated;
grant execute on function saytile.within_daily(uuid,bigint,bigint) to service_role;
create function public.st_reserve(p_uid uuid,p_recording uuid,p_epoch bigint) returns uuid language plpgsql security invoker set search_path='' as $$
declare c saytile.control; a saytile.accounts; lid uuid;
begin
 select * into c from saytile.control for update;
 select * into a from saytile.accounts where uid=p_uid for update;
 if not c.enabled or c.asr_hold<35000 or c.review_hold<1000000 then raise exception 'offline'; end if;
 if not found or not a.active or a.billing_hold or a.valid_until<=now() then raise exception 'no_entitlement'; end if;
 if exists(select from saytile.sessions where uid=p_uid and recording=p_recording) then raise exception 'already_admitted'; end if;
 if a.remaining_ms<35000 then raise exception 'quota'; end if;
 if (select count(*) from saytile.sessions where uid=p_uid and created_at>now()-interval '1 minute')>=12
 or (select count(*) from saytile.sessions where uid=p_uid and not ended and expires>now())>=2 then raise exception 'rate_limit'; end if;
 if not saytile.within_daily(p_uid,c.asr_hold+c.review_hold,c.user_day_micros) then raise exception 'quota'; end if;
 if c.committed_micros+c.asr_hold+c.review_hold>c.budget_micros then raise exception 'budget'; end if;
 insert into saytile.sessions(uid,recording,epoch,grant_generation) values(p_uid,p_recording,p_epoch,a.grant_generation) returning lease into lid;
 update saytile.accounts set remaining_ms=remaining_ms-35000 where uid=p_uid;
 update saytile.control set committed_micros=committed_micros+c.asr_hold;
 insert into saytile.usage(lease,op,reserved) values(lid,'audio',c.asr_hold);
 return lid;
end $$;

create function public.st_review(p_uid uuid,p_lease uuid,p_seq integer) returns void language plpgsql security invoker set search_path='' as $$
declare c saytile.control;
begin
 select * into c from saytile.control for update;
 if not c.enabled or c.review_hold<1000000 or not exists(select from saytile.sessions s join saytile.accounts a using(uid)
 where s.lease=p_lease and s.uid=p_uid and s.expires>now() and s.grant_generation=a.grant_generation and a.active and not a.billing_hold and a.valid_until>now()) then raise exception 'no_entitlement'; end if;
 if p_seq<=0 or exists(select from saytile.usage where lease=p_lease and op=p_seq::text) then raise exception 'already_admitted'; end if;
 if (select count(*) from saytile.usage where lease=p_lease)>=17 then raise exception 'rate_limit'; end if;
 if (select count(*) from saytile.usage u join saytile.sessions s using(lease) where s.uid=p_uid and u.op<>'audio' and not u.settled and u.created_at>now()-interval '100 seconds')>=2 then raise exception 'rate_limit'; end if;
 if not saytile.within_daily(p_uid,c.review_hold,c.user_day_micros) then raise exception 'quota'; end if;
 if c.committed_micros+c.review_hold>c.budget_micros then raise exception 'budget'; end if;
 insert into saytile.usage(lease,op,reserved) values(p_lease,p_seq::text,c.review_hold);
 update saytile.control set committed_micros=committed_micros+c.review_hold;
end $$;

create function public.st_settle(p_lease uuid,p_op text,p_ms integer,p_actual bigint,p_units jsonb) returns void language plpgsql security invoker set search_path='' as $$
declare u saytile.usage; s saytile.sessions;
begin
 perform 1 from saytile.control for update;
 select * into strict u from saytile.usage where lease=p_lease and op=p_op for update;
 if u.settled then return; end if;
 if p_ms not between 0 and 35000 or p_actual<0 then raise exception 'invalid_settlement'; end if;
 update saytile.usage set actual_micros=p_actual,units=p_units,settled=true where lease=p_lease and op=p_op;
 if p_actual is not null then
 update saytile.control set committed_micros=committed_micros+p_actual-u.reserved,enabled=enabled and p_actual<=u.reserved;
 end if;
 if p_op='audio' then
 update saytile.sessions set ended=true,milliseconds=coalesce(p_ms,35000) where lease=p_lease returning * into s;
 update saytile.accounts set remaining_ms=remaining_ms+35000-s.milliseconds where uid=s.uid and active and grant_generation=s.grant_generation;
 end if;
end $$;

create function public.st_customer(p_uid uuid,p_customer text default null) returns text language plpgsql security invoker set search_path='' as $$
declare result text;
begin
 insert into saytile.accounts(uid,customer) values(p_uid,p_customer)
 on conflict(uid) do update set customer=coalesce(saytile.accounts.customer,excluded.customer) returning customer into result;
 return result;
end $$;
-- Never grant twice from duplicate webhook endpoints or duplicate invoice events.
create function public.st_invoice(p_customer text,p_subscription text,p_invoice text,p_until timestamptz,p_ms bigint)
returns void language plpgsql security invoker set search_path='' as $$
declare a saytile.accounts;
begin
 select * into strict a from saytile.accounts where customer=p_customer for update;
 if p_until<=now() or (a.paid_until is not null and p_until<=a.paid_until) then return; end if;
 perform public.st_grant(a.uid,p_ms,p_until,'stripe.invoice.'||p_invoice,true);
 update saytile.accounts set subscription=p_subscription,paid_until=p_until where uid=a.uid;
end $$;

do $$ declare f regprocedure; begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in ('st_account','st_grant','st_reserve','st_review','st_settle','st_customer','st_invoice') loop
 execute format('revoke all on function %s from public,anon,authenticated',f);
 execute format('grant execute on function %s to service_role',f);
 end loop;
end $$;
commit;
