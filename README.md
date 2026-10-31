# BrightBots Procurement

The frontend reads authorized records and submits new requests to the separate Procurement Supabase database. Demo records and browser-local workflow mutations have been removed.

## Run

With Node.js 18 or newer:

```bash
npm start
```

Open http://localhost:3000. Use a **Procurement account** with the company email enabled in the employee directory. This is a separate Auth project; TaskOps passwords are not copied automatically. First-time users can choose **Create Procurement account**. Email confirmation is still enabled in the Supabase project; removing that step requires a project Auth configuration change, which is not exposed by the current connector. Signup emails depend on the project's Auth email configuration and provider limits.

Opening index.html directly may work, but localhost or an HTTPS static host is recommended for authentication and network requests.

## Data and access

- Records load from Supabase after sign-in, using existing row-level-security policies.
- Original request IDs, source row references, dates, item codes and Drive links are retained.
- Multiple items under one request ID remain separate item records.
- Tracking rows are used when the account cannot read full financial item records. Restricted details and unavailable amounts remain unavailable; they are never replaced with demo values.
- Real records remain in memory. They are not embedded in this public repository or saved in browser-local storage. Auth sessions use session storage and are cleared on sign-out.
- The frontend contains a browser-safe Supabase **publishable key**, not a service-role key or database password. Access protection comes from database RLS, not secrecy of the publishable key.
- The database currently contains an imported Sheet snapshot. Refresh reads the current **database**, not the latest Google Sheet. This change does not set up automatic Sheet synchronization.

The baseline checked during implementation contained **192 requests, 541 item rows and 909 catalog entries**. A user can see fewer rows according to existing database permissions. Auth accounts are managed separately in the Procurement project. Sign-in still follows the project’s current email-confirmation setting.

## Current behavior

This release supports **new request submission**. Existing workflow records and approvals remain read only. It supports overview, request tracking, stage queues, Select All for inspection, original fields, quotation comparison, linked Drive documents, catalog search, CSV export and imported stage review.

**New request** opens a multi-item form with live catalog search by name, column M code or column N category. The full signed-in employee name is displayed; the backend derives requester identity from Auth and the enabled employee directory. Column A is not displayed or searched.

**Save draft** keeps an unsubmitted draft in memory for this tab. **Submit request** calls the authenticated, security-invoker `submit_procurement_request` RPC. It creates the request, initial Request Approval items, tracking rows and audit entries in one transaction. A client token prevents duplicate creation on retry. If a network result is uncertain, the form locks its submitted values and offers Retry submission with the same token. Keep the tab open until the result is confirmed.

The approved database change is recorded in `database/submit_request.sql`. INSERT policies limit employees to their own initial requests. A narrow SELECT policy lets them read their own new initial-stage items. No UPDATE or DELETE access was added. Existing imported financial records retain their prior access rules. Approvals, existing-record edits, file uploads, payments and notification emails are not activated. TaskOps is unchanged. No new frontend Admin role, common dashboard or Source & readiness menu was introduced.

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

## Readability

The interface now uses a 16 px base, larger table and field text, 44 px form controls, fluid headings and responsive grids. On narrow screens, tables scroll within their own panels instead of shrinking text or forcing the entire page wider.
