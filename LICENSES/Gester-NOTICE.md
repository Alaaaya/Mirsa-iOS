# Gester adapter

`ios-app/PosterBoardAccess.m` adapts scoped container-query strategies from
Gester commit `7ed710ca6c4fb5bbf07729d96fddd2a622383d2f`, `src/BQCore.m`.
Original copyright 2026 KAMUI contributors. The complete MIT license is
`Gester-MIT.txt`, included in source and the application resources.

Mirsa tries class-13 traversal, class-7 with the application's actual signed
and usable app-group entitlement, class-2 stage/subpath probes within its own
Caches, and class-12 traversal. Targets are restricted to data-container roots
and UUID children. Token acquisition must also open the real target or its
verified lease alias. No foreign group is hardcoded. Each class-7 alias retains
its own original Caches backup until lease release; cleanup never recursively
deletes Caches or overwrites a conflicting backup. Class-2 probes clean up only
their unique temporary links/empty directories. The dangerous parent-Library
rename strategy is NOT implemented. No cache reset or global preference reset.

The Swift installer validates PosterBoard metadata, rejects redirected paths,
backs up its scoped preferences, and verifies destination SHA-256 readback.
Airlift transport staging cannot replace independent final-target verification.
Gallery registration and real-device compatibility are not proven by a copy.
No Placard or Pocket-Poster source has been copied into this adapter.

Existing VideoCAML GPL obligations and corresponding-source distribution
requirements remain unchanged. See VideoCAML-NOTICE.md.
