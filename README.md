# BrightBots Procurement

Separate Procurement Supabase app. TaskOps and the original Google Sheet are unchanged. Live hosting is intentionally deferred.

## Run

```bash
npm start
```

Open http://localhost:3000. Google sign-in works on localhost or HTTPS. Choose **Continue with Google** using an email enabled in the Procurement employee directory. Email/password account access remains available; saving stage actions and uploading stage files require an OAuth sign-in to verify the employee identity without an email-confirmation link.

In Supabase Auth URL Configuration, allow the exact app URL you are using, including your current tunnel URL. In Google Cloud, the authorized redirect URI remains:

```text
https://bezpksgfxkecfpwavndz.supabase.co/auth/v1/callback
```

The Google callback uses PKCE with a short-lived verifier bound to this browser tab. Provider tokens are not saved in browser storage. Supabase sessions use session storage and clear on sign-out. Keep OAuth client secrets out of GitHub and chat.

## Workflow

New requests save the request, items, tracking and audit atomically, with idempotent retries. The signed-in enabled employee supplies the requester identity. Drafts stay in tab memory only.

All ten original stages have forms and server-side owner checks: Request Approval, Quotation, Vendor Approval, PO, Fund Approval, Payment, Dispatch, QC, Invoice and Accounting. No new Admin role or common dashboard was introduced. Stage ownership follows the existing `stage_owners` configuration. Only the current assigned owner can save a stage; general browser UPDATE/DELETE privileges remain revoked.

Request Approval includes all pending items in a request and requires one decision for the whole request. Select All and apply-to-all controls support Vendor and Fund Approval. Up to 100 items can be saved together. Version checks reject stale changes, and retry tokens prevent duplicate stage actions. The database calculates PO base amounts, GST, payment allocation and balances. Invoice/bill upload remains mandatory for the Invoice stage. Audit entries record each action and its actor.

Item names are preserved. Codes come from Item Master column M, code categories from N. Column A is neither shown nor searched. Name/code/category searches cover all 909 catalog entries.

## Owner Drive and email setup

The configured owner is **`vidit@brightbots.in`**, as explicitly requested. The app creates a separate **Procurement Tracker Supabase** folder in Vidit's My Drive during the one-time Google connection. It reuses that app-marked folder on reconnection. The earlier empty Deepali folder is not used or modified. Other employees do not connect their personal Drives.

1. Enable Google Drive API and Gmail API in the OAuth client's Google Cloud project.
2. Sign into Procurement as the owner using Google.
3. Open **Drive & email → Authorize owner Google account**. Approve the app-created-files and send-email permissions and offline access. The Drive permission is limited to files created/accessed by this app (`drive.file`); the server pins uploads to its owner folder.
4. After the return to the app, enter the same OAuth client ID and client secret already configured in Supabase, then choose **Connect Drive & email**. The app sends them directly over HTTPS to its backend. The server validates the Google account, folder ownership and email-send scope before storing the grant encrypted in Supabase Vault.

A changed tunnel URL must be added to Supabase's allowed redirect URLs before authorizing. If the Google consent app is in Testing, the owner must be an allowed test user. A missing or revoked grant must be reauthorized.

Uploads are private, bound to an item/stage/actor, and limited to PDF, JPG/PNG/WebP, TXT, CSV, DOCX or XLSX up to 10 MB. New files download through authenticated app access; they are not made public or shared automatically. Existing Drive links keep their original sharing permissions.

Notifications are queued atomically for new requests and stage transitions, addressed to the existing stage owners, with Deepali CC matching the original script. Action saves attempt delivery after the commit. The owner can use **Retry pending notifications**. Failed deliveries stay queued; ambiguous sends are marked for mailbox review and are not automatically resent.

**Background retries are enabled every five minutes**, with the user's explicit approval. The scheduler calls the mail-only Edge worker using a random 256-bit dispatcher token encrypted in Vault. This token cannot log into Supabase, read arbitrary records, upload files or choose recipients; it can dispatch already-queued notifications only. No Supabase service-role key is stored as the dispatcher credential. Until the owner connects Google, worker runs return a waiting status without sending anything. Each run claims up to 10 pending/failed notifications; ambiguous sends remain for manual mailbox review. Worker source is `backend/google-services.ts`, with setup in `database/mail_worker.sql`.

## Data freshness

On 31 October 2026, the latest Procurement HTML sheet was checked: 192 request IDs and 541 item rows matched the database, with no new/changed request rows or identity conflicts. All 909 catalog entries were refreshed, including the current M/N code mapping. Imported history and locally created requests were preserved. This is a checked snapshot, not continuous Sheet synchronization; workflow changes now save in Supabase only.

Real business records, passwords and credentials are never embedded in this public repository. The frontend uses a publishable key; database RLS and authenticated RPCs enforce access. Google backend credentials are service-only in Vault. The Edge Function validates every browser JWT against Supabase Auth and checks the enabled employee before processing any operation. No service-role key is copied into the proposed worker.

## Verification

```bash
npm run check
npm test
```

20 automated tests cover mapping, pagination, PKCE, credential non-persistence, API authentication, stage controls, file access and queued recipients. `database/verify_workflow.sql` exercises a synthetic two-item request through all ten stages and rolls back every fixture. It checks wrong owners, whole-request approval, stale versions, field restrictions, retry idempotency, PO/GST calculations, partial-payment allocation, file references, audit and notification deduplication. No real email or file is sent by the tests.

Browser QA uses an isolated synthetic-data copy, not production credentials. Real Google sign-in, uploads and delivery still need the owner's one-time Google authorization and end-to-end account verification.

## Temporary tunnel

The existing Windows command is retained:

```powershell
& "C:\Users\MY PC\Downloads\cloudflared.exe" tunnel --url http://localhost:3000 --protocol http2
```

Permanent hosting and final cutover remain deferred.
