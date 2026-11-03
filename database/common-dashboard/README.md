# Trackers common dashboard

Weekly Review contains an admin-only link opening a separate read-only screen. Use Google sign-in with an active admin account in both trackers and keep the original tracker tab open. Password-only sessions cannot use the cross-project bridge.

The TaskOps and Procurement tabs include active employees in each source. Cumulative includes only emails present in both, normalized for case and surrounding spaces. Workload is current; performance uses the selected Monday–Sunday IST week. TaskOps counts scored task events, Procurement counts completed stage intervals; cumulative percentages pool counts, never average percentages. Shared stage responsibility may count an item for multiple employee rows; source cards deduplicate. Historical configured responsibility is labelled rather than presented as a verified actor.

Both Supabase projects deploy `trackers-common-dashboard` from the identical backend source with gateway JWT verification disabled so either project's token can reach it. The function itself verifies tokens with the issuing Auth server and checks protected active-admin profiles in both databases. It calls a service-only aggregate RPC and streams only change notices. No foreign service key, refresh token, or credential is stored. Browser access tokens pass only through origin/window-checked messages from the opening tracker tab.

Realtime listens to a private non-PII change counter. Server-side streams authorize on entry and every 20 seconds; clients refresh on changes and every 30 seconds as a fallback. Failures are labelled, failed data is cleared, and cumulative results require both sources. Source update times are displayed.

Provisioning was applied to both projects on 2026-11-03. Apply signal.sql followed by the corresponding source SQL for a new installation; deploy the backend in each project using its own standard Supabase environment. No Drive/Gmail configuration or task/stage workflow was changed.

Validation: Procurement syntax checks and 39 tests; TaskOps TypeScript/Vite build; real aggregate SQL and direct authenticated-access denial checks. Browser layout, tab handoff and all three views verified using synthetic fixtures. A real signed-in admin/live-change browser session remains to be verified after updating the hosted or local frontends.
