# Operational integration — future phase

The current scope is the frontend. These boundaries should be retained when the app becomes operational:

1. Use the original Procurement scripts and latest `Procurement HTML` Sheet as the workflow reference.
2. Preserve existing stage responsibilities and Item Master permissions. Do not assume that TaskOps Admin roles apply to Procurement.
3. Replace illustrative records with authorized backend reads; enforce each stage permission on the server/database.
4. Replace preview save handlers with transactional, validated writes and concurrency checks. Keep history append-only.
5. Preserve original request IDs, item identities, original dates and source lineage; do not deduplicate distinct items merely because they share a request ID.
6. Connect file inputs to authorized Google Drive uploads, preserving file IDs and links.
7. Add audited notifications, retry handling and duplicate protection only during operational integration.
8. Validate TAT against the original review rules: 09:30–17:30 IST, excluding Sundays and second Saturdays; Invoice + Accounting share an eight-working-hour review target.
9. Replace sample hour indicators with verified working-calendar calculations. Do not publish sample grades as real employee performance.
10. Reconcile the final Sheet snapshot and verify complete journeys before switching the live workflow.

No backend credentials belong in this repository's frontend assets. The sample preview currently requires no credentials.
