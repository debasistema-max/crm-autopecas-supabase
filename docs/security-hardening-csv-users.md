# Security hardening - CSV exports and user editing

Status: local implementation and regression tests only. No frontend deployment,
Edge Function deployment, hosted database change or real password change.
MFA is deferred at the user's request on 2026-10-27. The migration-118 portfolio
fix is already applied in production and remains separate from this frontend work.

## CSV formula protection

The shared formatter now quotes and escapes every cell, including object-export
headers. Formula-like text gets a protective tab inside the quoted field before
it is downloaded. The check includes leading whitespace/control characters,
selected invisible formatting characters, apostrophes, and full-width formula
prefixes. Existing numeric JavaScript values remain numeric text, including
negative amounts. Numeric-looking strings remain untrusted text.

The batch exporter delegates to the same formatter instead of maintaining a
weaker independent prefix check. The shared download path covers customer
registration reports, order/quotation reports, fiscal pending reports and
commercial lists. No stored field, total, quantity or permission is changed.
XLSX and PDF behavior is not modified.

Trade-off: dangerous text acquires a tab in its exported value. These CSV files
are intended for human viewing in spreadsheets, not lossless interchange or
reimport into the SAP pipeline. Do not strip the protective prefix and treat the
result as safe. There is no universal CSV mitigation for all spreadsheet apps
and resave/reopen behaviors; use typed XLSX when appropriate and keep spreadsheet
applications patched. The implementation follows the Excel-oriented protection
described by [OWASP CSV Injection](https://owasp.org/www-community/attacks/CSV_Injection).

Tests use fictional strings and simulated downloads. They verify serialized
output, BOM, quotes/delimiters, multiline fields, header protection, ordinary
text, numeric preservation, no mutation of input rows and URL cleanup. They do
not execute formulas in Excel/LibreOffice or certify every spreadsheet version.

## Honest user/password administration

The password field is for new accounts only. Editing an existing profile clears,
disables and hides that field. Starting a new account clears the entire form and
restores the initial-password requirement.

The persistence adapter rejects a nonempty password for an existing user before
issuing any query or write, instead of silently ignoring it. Successful profile
editing explicitly reports that the password was not changed, after the list
has refreshed. The existing login password-recovery flow remains the route for
changing a password. No privileged password-reset API was introduced.

This resolves the misleading success condition, not every identity-provisioning
concern: public Auth signup, profile/Auth email synchronization and migration to
an ADMIN-authorized server provisioning endpoint require separate review. This
frontend guard does not replace RLS or server-side Auth authorization.

Tests mock Auth, profile reads/writes and audit events. They verify that rejected
password edits produce no API call, new-account behavior remains supported,
passwords are not included in profile/audit payloads, forms reset correctly and
errors do not display success. No real account was created or changed.

## Validation and rollout

- Full suite passed on 2026-10-27: 217 tests (120 static/UI contracts, 53
  session/document/security tests and 44 Python tests). JavaScript syntax,
  migration sequence and `git diff --check` also passed. No manual browser or
  actual spreadsheet-application check was performed in this stage.
- Run `npm test`, including `csv-export-security.test.cjs` and
  `user-password-edit-security.test.cjs`.
- Review the diff and perform manual checks with fictional reports/accounts in
  an isolated or recovered homologation environment before publication.
- Updated entry-point cache versions cover `format.js`, `supabase_store.js` and
  `users.js`. Login, role menus and session-guard contracts remain in the suite.
- Publishing requires separate authorization; there is no new migration in
  this stage. Do not reapply migration 118 just to publish these frontend fixes.
- Audit findings on trusted logs, confidential client columns, product DML and
  full current-version recovery remain pending. MFA remains deferred, not fixed.
