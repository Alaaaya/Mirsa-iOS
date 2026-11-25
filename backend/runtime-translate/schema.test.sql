-- Run only in disposable local Postgres with schema.sql installed and fixture auth user.
begin;
insert into auth.users(id) values ('11111111-1111-4111-8111-111111111111');
insert into public.mirsa_runtime_caps(token_hash,user_id,bundle_id,revision,expires_at) values
 (repeat('a',64),'11111111-1111-4111-8111-111111111111','com.example.app',repeat('b',64),now()+interval '1 day');
do $$
declare ok boolean; i integer;
begin
 if has_function_privilege('authenticated','public.mirsa_runtime_reserve(uuid,text,text,text,text,integer)','execute') then raise exception 'RPC exposed'; end if;
 if has_table_privilege('authenticated','public.mirsa_runtime_caps','select') then raise exception 'caps exposed'; end if;
 ok := public.mirsa_runtime_reserve(null,repeat('a',64),'com.other.app',repeat('b',64),'missing',1);
 if ok then raise exception 'cross app'; end if;
 ok := public.mirsa_runtime_reserve(null,repeat('a',64),'com.example.app',repeat('c',64),'missing',1);
 if ok then raise exception 'cross revision'; end if;
 update public.mirsa_runtime_caps set expires_at=now()-interval '1 minute';
 if public.mirsa_runtime_reserve(null,repeat('a',64),'com.example.app',repeat('b',64),'missing',1) then raise exception 'expired'; end if;
 update public.mirsa_runtime_caps set expires_at=now()+interval '1 day',revoked=true;
 if public.mirsa_runtime_reserve(null,repeat('a',64),'com.example.app',repeat('b',64),'missing',1) then raise exception 'revoked'; end if;
 update public.mirsa_runtime_caps set revoked=false;
 for i in 1..10 loop
 if not public.mirsa_runtime_reserve(null,repeat('a',64),'com.example.app',repeat('b',64),'missing',1) then raise exception 'early quota'; end if;
 end loop;
 if public.mirsa_runtime_reserve(null,repeat('a',64),'com.example.app',repeat('b',64),'missing',1) then raise exception 'minute limit'; end if;
 update public.mirsa_runtime_usage set minute=now()-interval '2 minutes';
 update public.mirsa_runtime_caps set chars=32768;
 if public.mirsa_runtime_reserve(null,repeat('a',64),'com.example.app',repeat('b',64),'missing',1) then raise exception 'cap chars'; end if;
 update public.mirsa_runtime_caps set chars=0,requests=256;
 if public.mirsa_runtime_reserve(null,repeat('a',64),'com.example.app',repeat('b',64),'missing',1) then raise exception 'cap requests'; end if;
 update public.mirsa_runtime_caps set requests=0;
 update public.mirsa_runtime_usage set requests=100;
 if public.mirsa_runtime_reserve(null,repeat('a',64),'com.example.app',repeat('b',64),'missing',1) then raise exception 'user requests'; end if;
 update public.mirsa_runtime_usage set requests=0,chars=65536;
 if public.mirsa_runtime_reserve(null,repeat('a',64),'com.example.app',repeat('b',64),'missing',1) then raise exception 'user chars'; end if;
 update public.mirsa_runtime_usage set chars=0,issues=12;
 if public.mirsa_runtime_reserve('11111111-1111-4111-8111-111111111111',null,'com.example.app',repeat('b',64),'issue',0) then raise exception 'issue limit'; end if;
end $$;
rollback;
