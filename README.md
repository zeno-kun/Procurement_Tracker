# BrightBots Procurement

The frontend reads existing authorized records from the separate Procurement Supabase database. Demo records and browser-local workflow mutations have been removed.

## Run

With Node.js 18 or newer:

```bash
npm start
```

Open http://localhost:3000. Use a **Procurement account** with the company email enabled in the employee directory. This is a separate Auth project; TaskOps passwords are not copied automatically. First-time users can choose **Create Procurement account**, confirm the email, and return to sign in. Signup emails depend on the project's Auth email configuration and provider limits.

Opening index.html directly may work, but localhost or an HTTPS static host is recommended for authentication and network requests.

## Data and access

- Records load from Supabase after sign-in, using existing row-level-security policies.
- Original request IDs, source row references, dates, item codes and Drive links are retained.
- Multiple items under one request ID remain separate item records.
- Tracking rows are used when the account cannot read full financial item records. Restricted details and unavailable amounts remain unavailable; they are never replaced with demo values.
- Real records remain in memory. They are not embedded in this public repository or saved in browser-local storage. Auth sessions use session storage and are cleared on sign-out.
- The frontend contains a browser-safe Supabase **publishable key**, not a service-role key or database password. Access protection comes from database RLS, not secrecy of the publishable key.
- The database currently contains an imported Sheet snapshot. Refresh reads the current **database**, not the latest Google Sheet. This change does not set up automatic Sheet synchronization.

The baseline checked during implementation contained **192 requests, 541 item rows and 909 catalog entries**. A user can see fewer rows according to existing database permissions. At verification time there were **no Procurement Auth accounts registered**; account creation/confirmation is required before the first signed-in use.

## Current behavior

This release is **read only**. It supports overview, request tracking, stage queues, Select All for inspection, original fields, quotation comparison, linked Drive documents, catalog search, CSV export and imported stage review.

New requests, approvals, edits, uploads, payments and notifications are not enabled. Existing workflow writes and TaskOps remain unchanged. No new frontend Admin role, common dashboard, or Source & readiness menu was introduced. Existing database policies are not modified by this repository change.

Historical measurements use configured-owner attribution when the original actor was not recorded. Current open-stage timing is workload, not a finalized employee score. Invoice + Accounting share the legacy eight-working-hour target.

## Validate

```bash
npm run check
npm test
```

Tests use synthetic records, not production fixtures or credentials. Signed-in browser verification requires an actual authorized Procurement account and is not replaced by the model tests.

## Host

Serve the repository root as static files. For Cloudflare Pages, no build command is required and the output directory is the repository root. Relative asset paths also support a GitHub Pages repository subpath, when Pages is available for the repository.

Do not commit business-data exports, auth sessions, passwords or service-role keys. Do not add business records as static JSON to bypass authentication.
