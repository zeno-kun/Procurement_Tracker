# Operational integration — next phase

Existing records are connected through authenticated read-only Supabase reads. The original Google Sheet remains the live workflow until a separate cutover.

Remaining work:

1. Complete the first authorized Procurement account setup and verify signed-in browser reads.
2. Verify stage-by-stage permissions against the original script. This frontend change does not alter existing database policies or introduce an Admin role.
3. Implement validated transactional writes, stage ownership checks and concurrency protection, keeping history append-only.
4. Connect document inputs to authorized Google Drive uploads.
5. Add audited notifications with retry and duplicate protection.
6. Reconcile the latest Sheet without overwriting history or duplicating items, then validate complete journeys before live cutover.

Never weaken authentication or embed private business records in the public frontend to make data visible. TaskOps and the common dashboard are outside this change.
