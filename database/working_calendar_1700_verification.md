# Procurement calendar and compact UI verification

2026-11-05: Procurement working time is 09:30–17:00 Asia/Kolkata, Monday–Saturday, excluding Sundays and second Saturdays. Original start-anchored 15-minute measurement increments and stage TAT limits remain in use. The review yellow allowance remains eight working hours.

`working_calendar_1700.sql` changes the working-hours function and common dashboard read model. It does not update business rows or stored stage-event results. Reports and the common dashboard recalculate grades with the current calendar; saved historical grades remain audit evidence of the previous calendar.

Verified database boundaries: a full working day returns 7.50 hours; 17:00–17:30, Sunday and second Saturday return 0.00. The common dashboard snapshot for 2–8 November returns 3 measured completed stages, all Green.

Integrity: 193 requests, 542 request items and 3,614 stage events remain. Stage-event checksum before/after: `e03f8ce9e0d1def606277d5ee03e675e`. Across 3,587 completed report intervals, 123 recalculated grades differ from the saved audit grade after the shorter working day. TaskOps score events and scoring rules were not modified. Cumulative percentages still pool both trackers' measured counts for common employees.

UI: blank values render without placeholder dashes; real zero values remain. Three quotation vendor groups align on wide screens and wrap responsively. Weekly Target Entry uses compact legacy owner groups and inline count/percentage fields; carry-forward validation and version checks remain. Apply-to-selected controls skip disabled/unchecked items and require an explicit Save.

Browser checks used synthetic local fixtures only. No requests, stage actions, target submissions, file uploads or emails were sent to production during UI verification.
