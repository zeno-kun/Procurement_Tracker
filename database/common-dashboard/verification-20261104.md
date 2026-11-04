# Verification — 4 November 2026

Current week: 2–8 November 2026. Previous week: 26 October–1 November 2026. Database checks are read-only except notification tests in a rolled-back transaction.

| Source / week | Green | Yellow | Red | Measured | Points | App comparison |
|---|---:|---:|---:|---:|---|---|
| TaskOps current | 1 | 0 | 10 | 11 | 3 / 33 = 9.1% | Matches native Weekly Review |
| TaskOps previous | 5 | 0 | 25 | 30 | 15 / 90 = 16.7% | Matches native Weekly Review |
| Procurement current | 3 | 0 | 0 | 3 | TAT grades | Matches independent interval calculation |
| Procurement previous | 1 | 0 | 1 | 2 | TAT grades | Matches independent interval calculation |

No TaskOps event had points inconsistent with the saved Green=3 / Yellow=1 / Red=0 colour. No completed Procurement interval had a stored colour inconsistent with independently recalculated working hours and its stage TAT. No interval completion-date mismatch was found.

24 active employee identities matched across both sources. Matching used normalized email hashes for this audit. Current combined counts: Green 4, Yellow 0, Red 10, measured 14; Green rate 28.5714%. This pools measured counts and is distinct from TaskOps points percentage. Shared Procurement ownership remains explicitly labelled. These figures describe the audit snapshot and will change with live work.

Progress counts before and after: Procurement 193 requests, 542 items, 3614 stage events, 2 uploaded-file records, 0 weekly targets. Stages: PO 1, QC 115, Payment 91, Rejected 40, Completed 256, Quotation 12, Vendor Approval 27. TaskOps 1271 tasks, 1221 score events, 82 weekly targets, 374 due-date-history records. Counts and stage distribution were unchanged. No sample notification was sent; the outbox retained its 4 previously sent records.

Email content tests cover all 12 outcomes/stages, correct configured recipients, readable request IDs, all item lines in the notified stage, saved quotation links, required instructions, duplicate suppression and once-per-item creation refresh. The tests roll back completely, so the scheduled worker cannot see them. Notifications use structured plain text through the existing Gmail dispatcher. The attempted HTML dispatcher deployment was rejected by automatic review; no Google/Drive/Gmail service update was applied.

Backend common-dashboard version 2 deployed in both projects. Password and Google admin sessions accepted in authorization tests; anonymous, forged-role, inactive and non-admin sessions remain denied. Procurement 40 automated tests pass; TaskOps production build passes. Rules modal checked in browser with synthetic preview data. A real user login was not available in the test browser.
