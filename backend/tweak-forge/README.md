# tweak-forge
Edge function (Mirsa Supabase) plus an isolated Theos builder.
- Needs secrets on the edge function: LLM_API_KEY (OpenAI-compatible; optional LLM_BASE_URL, LLM_MODEL), TWEAK_BUILDER_URL, TWEAK_BUILDER_SECRET. Unset values return 503 llm_not_configured / builder_not_configured, never fake output.
- Apply schema.sql. Rate limits per user per hour (translate 30, generate 20, build 20, publish 5), enforced server side after Supabase auth.
- builder/: run on a Linux Docker host (not Edge, not the sandbox). Every build is a --network none, read-only, cap-dropped container with no secrets. Generated code is also screened by contract.mjs (no processes, network, dlopen, asm, file deletion).
- Settings toggles are compile-time macros, changing one rebuilds. Crash guard is compiled into the dylib (2 consecutive crashes disable it).
- Tests: node --test contract.test.mjs
