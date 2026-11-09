begin;
create function public.st_revoke_subscription(p_customer text,p_subscription text,p_event text) returns void language plpgsql security invoker set search_path='' as $$
declare a saytile.accounts;
begin
 select * into a from saytile.accounts where customer=p_customer and subscription=p_subscription for update;
 if found then perform public.st_grant(a.uid,0,now(),p_event,false); end if;
end $$;
create function public.st_billing_hold(p_customer text,p_event text) returns void language plpgsql security invoker set search_path='' as $$
declare a saytile.accounts;
begin
 select * into a from saytile.accounts where customer=p_customer for update;
 if found then
 insert into saytile.audit(uid,external_id,action) values(a.uid,p_event,'merchant_review') on conflict do nothing;
 if found then update saytile.accounts set billing_hold=true where uid=a.uid; end if;
 end if;
end $$;
create function public.st_reconcile(p_lease uuid,p_op text,p_actual bigint,p_reference text) returns void language plpgsql security invoker set search_path='' as $$
declare u saytile.usage;
begin
 perform 1 from saytile.control for update;
 select * into strict u from saytile.usage where lease=p_lease and op=p_op for update;
 if p_actual is null or p_actual<0 or nullif(p_reference,'') is null then raise exception 'invalid_invoice'; end if;
 if u.actual_micros is not null then return; end if;
 if not u.settled and exists(select from saytile.sessions where lease=p_lease and expires>now()) then raise exception 'operation_in_progress'; end if;
 update saytile.usage set actual_micros=p_actual,settled=true where lease=p_lease and op=p_op;
 update saytile.control set committed_micros=committed_micros+p_actual-u.reserved,enabled=enabled and p_actual<=u.reserved;
 insert into saytile.audit(external_id,action) values('provider.'||p_reference,'cost_reconciled');
end $$;
revoke all on function public.st_reconcile(uuid,text,bigint,text),public.st_billing_hold(text,text),public.st_revoke_subscription(text,text,text) from public,anon,authenticated;
grant execute on function public.st_reconcile(uuid,text,bigint,text),public.st_billing_hold(text,text),public.st_revoke_subscription(text,text,text) to service_role;
commit;
