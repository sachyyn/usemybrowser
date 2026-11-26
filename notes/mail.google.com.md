# Gmail (mail.google.com)
Recipe line: run on v2 (recipe header says verified 2026-11-26). Other lines: carried over from v1 notes, not re-verified on v2. <t> = tab id.

## Search and list
- Fastest: `umb recipe gmail-search '{"query":"from:someone@example.com"}'` prints `date | from | subject | unread|read`, newest first. Add `"open":true` to read the newest body (opening marks it read). `"account":1` for the second signed-in account.
- By hand: `umb open "https://mail.google.com/mail/u/0/#search/<url-encoded query>"`.
- Results are not always in date order. Sort by the row's date, do not take the first row as newest.
- Rows: `tr.zA`; sender `.yW span`; subject `.bog`; date `.xW span` (its `title` has the full date); unread rows have class `zE`.

## Read an email
- Body only: `umb text <t> .a3s`. The sidebar is noise.
- A subject search for meeting invitations misses invites with other subjects and calendar-only events.
