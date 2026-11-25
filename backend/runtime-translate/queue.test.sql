begin;
insert into auth.users values ('33333333-3333-4333-8333-333333333333');
insert into public.mirsa_runtime_caps(token_hash,user_id,bundle_id,revision,expires_at)
values(repeat('f',64),'33333333-3333-4333-8333-333333333333','com.example.queue',repeat('a',64),now()+interval '1 day');
do $$
declare n integer; v jsonb; x text; i integer;
begin
 if has_table_privilege('authenticated','public.mirsa_runtime_labels','select') or
 has_function_privilege('anon','public.mirsa_runtime_refresh(text,text,text)','execute') then raise exception 'public queue access'; end if;
 n:=public.mirsa_runtime_queue(repeat('f',64),'com.other.app',repeat('a',64),'[{"text":"设置"}]');
 if n<>0 then raise exception 'cross app queued';end if;
 n:=public.mirsa_runtime_queue(repeat('f',64),'com.example.queue',repeat('b',64),'[{"text":"设置"}]');
 if n<>0 then raise exception 'cross revision queued';end if;
 n:=public.mirsa_runtime_queue(repeat('f',64),'com.example.queue',repeat('a',64),'[{"text":"设置"},{"text":"设置"}]');
 if n<>1 then raise exception 'dedupe failed';end if;
 if public.mirsa_runtime_queue(repeat('f',64),'com.example.queue',repeat('a',64),'[{"text":"设置"}]')<>0 then raise exception 'persistent dedupe failed';end if;
 if public.mirsa_runtime_refresh(repeat('f',64),'com.example.queue',repeat('a',64))<>'[]'::jsonb then raise exception 'unreviewed leaked';end if;
 update public.mirsa_runtime_labels set translation='الإعدادات',resolved_at=now() where user_id='33333333-3333-4333-8333-333333333333';
 v:=public.mirsa_runtime_refresh(repeat('f',64),'com.example.queue',repeat('a',64));
 if v->0->>'translation'<>'الإعدادات' then raise exception 'OTA absent';end if;
 if public.mirsa_runtime_refresh(repeat('f',64),'com.other.app',repeat('a',64))<>'[]'::jsonb then raise exception 'cross app leaked';end if;
 for i in 1..12 loop
 x:=public.mirsa_runtime_anomaly(repeat('f',64),lpad(i::text,64,'0'),600,4,12);
 if i<4 and x<>'ok' then raise exception 'premature throttle';end if;
 if i between 4 and 11 and x<>'throttled' then raise exception 'throttle first missing';end if;
 end loop;
 if x<>'revoked' then raise exception 'clear threshold no revocation';end if;
 if public.mirsa_runtime_reserve(null,repeat('f',64),'com.example.queue',repeat('a',64),'dictionary',1) then raise exception 'revoked dict accepted';end if;
 if public.mirsa_runtime_refresh(repeat('f',64),'com.example.queue',repeat('a',64))<>'[]'::jsonb then raise exception 'revoked read accepted';end if;
 if public.mirsa_runtime_queue(repeat('f',64),'com.example.queue',repeat('a',64),'[{"text":"其他"}]')<>0 then raise exception 'revoked queue accepted';end if;
end $$;
rollback;
