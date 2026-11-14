# Gester adapter

`ios-app/PosterBoardAccess.m` adapts the narrow class-13 container-query lease
from Gester, commit `7ed710ca6c4fb5bbf07729d96fddd2a622383d2f`,
`src/BQCore.m` (query helper and class-13 strategy).
Original copyright 2026 KAMUI contributors. The complete MIT license is
`Gester-MIT.txt`, included in source and the application resources.

Mirsa modifications restrict destinations to data-container roots and UUID
children, release leases after use, and omit all rename/symlink/reset fallbacks.
The Swift installation/backup/readback implementation is separate Mirsa code.
No Placard or Pocket-Poster source has been copied into this adapter.

The existing VideoCAML GPL obligations and corresponding-source distribution
requirements remain unchanged. See VideoCAML-NOTICE.md.
