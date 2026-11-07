-- Apply after schema.sql. Additive; existing 15-minute clients remain compatible.
create or replace function public.mirsa_ota_reserve_v2(
 p_owner uuid,p_token text,p_bytes bigint,p_metadata jsonb,p_seconds integer
) returns void language plpgsql security definer set search_path=public as $$
begin
 if p_seconds not in (900,172800) then raise exception 'lifetime'; end if;
 -- Existing reserve performs global locking, all durable quotas and insertion.
 perform public.mirsa_ota_reserve(p_owner,p_token,p_bytes,p_metadata);
 update public.mirsa_ota_jobs set expires_at=created_at+make_interval(secs=>p_seconds)
 where token=p_token and owner=p_owner;
end $$;
revoke all on function public.mirsa_ota_reserve_v2(uuid,text,bigint,jsonb,integer) from public,anon,authenticated;
grant execute on function public.mirsa_ota_reserve_v2(uuid,text,bigint,jsonb,integer) to service_role;
