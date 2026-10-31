# Procurement operational integration

Applied in the Procurement project only:

1. `database/submit_request.sql`: own-request creation with RLS and transactional RPC.
2. `database/operational_workflow.sql`: stage RPCs, narrow current-owner reads, upload metadata and email outbox. No general browser UPDATE or DELETE privileges.
3. `database/stage_request_read_fix.sql`: private authorization helper avoids circular RLS between requests/items/tracking.
4. `database/google_services.sql`: service-only encrypted Google configuration, queue claiming and owner connection status.
5. `database/stage_identity_and_batch_checks.sql`: OAuth identity and whole-request consistency checks.
6. `database/private_connection_status.sql`: connection-status implementation stays private behind a security-invoker RPC.
7. `database/mail_worker.sql`: explicitly approved five-minute dispatcher with a mail-only random token in Vault.
8. `database/switch_google_owner_vidit.sql`: user-approved owner change to vidit@brightbots.in; old grants cannot be used after switching; the new folder is created by the app in Vidit’s Drive during authorization.

The `procurement-google-services` Edge Function is deployed from `backend/google-services.ts`. Gateway JWT checking is disabled because the function performs its own JWT validation against `/auth/v1/user` on every browser request before checking employee, owner and item permissions. Anonymous requests return 401. It never accepts arbitrary Google URLs, Drive destinations or mail recipients from callers.

The owner must complete the Drive/email authorization described in README. No Google credential is available from the ChatGPT Drive connection to a standalone app; provider access is separately authorized and stored in Vault. Do not paste secrets into chat or source.

Notifications are attempted after app actions and through the owner's retry button. The user explicitly approved scheduled retries. A five-minute cron job uses a random mail-only token, never a Supabase API key. The deployed Edge handler authenticates this token only for `mail_worker`, processes database-defined recipients, and waits without sending until Google is connected. Normal browser operations continue to require a validated Supabase user JWT.

Latest source check: Procurement HTML modified 29 October 2026 09:10:37.938 UTC; checked 31 October. 541 request items unchanged; 909 catalog entries refreshed. The source Sheet remains read-only to this migration. No destructive refresh, ID replacement, history deletion, common dashboard or TaskOps change was performed.

Before live cutover: finish owner Google setup, verify Google login/Drive/email with real accounts, review role access, reconcile any later Sheet changes, and choose permanent hosting. Hosting is intentionally deferred by the user.
