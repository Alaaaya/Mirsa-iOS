import {StagingAdmission27} from './staging-admission27.ts';
function ok(value: boolean, label: string) { if (!value) throw new Error(label); }
Deno.test('staging 20k label signing retries admitted, minute and concurrency finite', () => {
  const a = new StagingAdmission27();
  for (let i=0;i<20000;i++) { ok(a.enter(60000),'generous admission'); a.leave(); }
  ok(!a.enter(60000),'finite minute');
  for (let i=0;i<32;i++) ok(a.enter(120000),'next minute and concurrency');
  ok(!a.enter(120000),'finite concurrent');
  for (let i=0;i<32;i++) a.leave();
  ok(a.enter(120000),'slot released'); a.leave();
});
Deno.test('staging flood configuration cannot become unlimited', () => {
  for (const value of [Infinity,NaN,0,-1,100001]) {
    let rejected=false; try {new StagingAdmission27(32,value);} catch {rejected=true;}
    ok(rejected,'invalid finite configuration');
  }
});
Deno.test('disposable database concurrent overlapping chunks charge once', async () => {
  if (!Deno.env.get('MIRSA_FAIR_DISPOSABLE27')) return;
  const sql = async (text: string) => {
    const result=await new Deno.Command('/usr/bin/psql',{args:['-XqAt','-v','ON_ERROR_STOP=1','-c',text],stdout:'piped',stderr:'piped'}).output();
    if (!result.success) throw new Error(new TextDecoder().decode(result.stderr));
    return new TextDecoder().decode(result.stdout).trim();
  };
  // The disposable SQL suite leaves exactly ten minute admissions available.
  const reserve="select public.mirsa_runtime_reserve(null,repeat('d',64),'com.fair.app',repeat('b',64),'refresh',0)";
  const results=await Promise.all(Array.from({length:30},()=>sql(reserve)));
  ok(results.filter(x=>x==='t').length===10,'serialized finite minute ceiling');
  await sql("update public.mirsa_runtime_usage set minute_requests=0 where user_id='22222222-2222-4222-8222-222222222222'");
  await Promise.all(Array.from({length:30},()=>sql("select public.mirsa_runtime_queue(repeat('d',64),'com.fair.app',repeat('b',64),'[{\"text\":\"Concurrent\"},{\"text\":\"Hello\"}]')")));
  ok(await sql("select chars from public.mirsa_runtime_usage where user_id='22222222-2222-4222-8222-222222222222'")==='15','concurrent overlap once only');
});
