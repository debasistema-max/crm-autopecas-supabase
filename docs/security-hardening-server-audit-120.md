# Server audit boundary - migration 120

Status: local implementation only, branch `codex/security-server-audit`.
Production remains on migration 119. No deployment, hosted database change or
real account/customer mutation was performed in this stage. MFA stays deferred.

## What changes

- Browser INSERT, UPDATE and DELETE on `logs` are revoked, including column-level
  grants. The permissive `logs_insert` policy is removed. Read permissions and
  the existing session/RLS restrictions are preserved.
- New `audit_source` defaults to `LEGACY_UNVERIFIED`: existing records are kept,
  not deleted, rewritten or retroactively certified, even if some were already
  produced by old server code.
- A BEFORE INSERT trigger runs as INVOKER. It rejects writers other than the
  trusted database/server roles and derives SERVER provenance and database time.
  It is deliberately not SECURITY DEFINER, which would hide the real writer.
- Existing RPC/Edge audit inserts continue to work under their trusted owner or
  service role. Trigger ownership/roles must be confirmed at rollout time.
- Profiles, carriers, client registrations, company settings and generic
  settings get transactional row-change audit triggers. They derive actor and
  record ID on the server. No-op/timestamp-only changes are skipped.
- New form-related events retain changed-field names and safe before/after
  values for role/active/status, not copies of contact information or passwords.
- Client saves already audited by migration 119 and order/quotation/import RPC
  events are not duplicated. No pricing, import or document logic is changed.

The browser no longer submits LOGIN/LOGOUT or separate post-save audit records
for the covered forms. This avoids errors after a committed save when a second,
browser-driven audit request fails. The old `supabaseLog` entry point fails
closed instead of becoming a generic privileged append API. The obsolete,
unloaded `supabase_import_fix.js` path is not reenabled; the supported manual
import uses the existing transactional import RPCs.

The Logs table shows provenance explicitly: Servidor or Legado (nao verificado).
The column is escaped/rendered with fixed labels; it is not supplied by a user.

## Session semantics

An AFTER trigger observes real winner changes in `app_sessions` without replacing
`claim_app_session`, `release_app_session`, their locks or monotonic guards.

- A new winning application session records LOGIN once.
- Repeated claims/status checks do not create repeated LOGIN events.
- A matching release records LOGOUT once; stale releases cannot log out the
  winner or forge its LOGOUT. Auth expiration alone is not mislabeled as an
  explicit logout.
- B2B Auth users without an internal profile use nullable logs.user_id and a B2B
  label; the affected Auth identity is the record ID.
- A LOGIN event proves a database application-session transition, not every Auth
  sign-in attempt. Supabase Auth's own audit remains the source for attempts.

Audit failures abort their enclosing operation, including session transitions.
This is fail-closed by design: an unavailable/full audit database can block login
or covered writes. Confirm capacity, backup and alerts before enabling it.

## Validation completed locally

- `npm test`: 236 tests passed (120 static/UI contracts, 72 session/document/
  security tests, 44 Python tests). Syntax/migration sequence checks passed.
- PostgreSQL disposable lab with no network, no published ports and only
  fictional identities/data: migration 120 compiled and regression passed.
- Tests cover fabricated browser events (also ADMIN), rewriting/deleting logs,
  accidental regrant defense, preserved legacy provenance, authoritative actor,
  minimized contacts/passwords, role before/after, timestamp-only updates,
  mutation/delete audit, existing client RPC, service role compatibility,
  single-session replacement, repeated claims/releases, stale sessions, B2B and
  transaction rollback when an audit fails.
- Browser unit mocks assert that session/form flows do not append audit records
  and that provenance is displayed safely. No real credentials were used.

The reduced SQL fixture loads audited session/RLS helpers and migrations
118-120. Fiscal/operational calculations remain stubs. It is not a full restored
Supabase instance or an authenticated PostgREST/browser end-to-end test.

## Controlled rollout - separate authorization required

1. Review the diff and current remote metadata. Confirm production migration 119,
   trusted function/table owners, all target tables, expected logs columns and
   no colliding trigger/function names. Preserve definitions/grants privately.
2. Take and validate a fresh backup. Check disk capacity and log-write health;
   don't repeat the earlier full-disk homologation incident in production.
3. Validate in isolated/recovered homologation, including actual PostgREST, ADMIN
   forms, login/logout, B2B activation and a document/import flow with fixtures.
4. Schedule a short coordinated migration/frontend window. Staff must finish
   pending edits first. Apply migration 120 transactionally before publishing
   the frontend that selects audit_source. Stop on failure; do not partially
   apply the SQL or auto-restore unsafe browser grants.
5. Publish the cache-busted frontend and refresh old tabs. Old forms can show a
   post-save log error after the revocation even though their real write was
   already committed and audited by the trigger. Avoid retrying such saves in
   old tabs; reload after release. Old login/logout flows still release/claim
   through their existing guards, but can warn about obsolete browser logging.
6. Read back grants, policies, trigger definitions and provenance. Verify PUBLIC
   and anon/authenticated cannot append logs, normal RPC/server writers work,
   RLS remains enabled and 119's client-column protection is unchanged.
7. Verify assets/cache versions and monitor safe error metadata. Do not create
   users/documents or run cross-portfolio mutation tests in production.

## Limits

SERVER means generated by trusted server/database code, not a cryptographic or
external immutable ledger. Database administrators and service-role holders are
trusted; their access and secret protection need independent controls. This does
not make an existing vulnerable RPC safe merely because its log is server-made.

This stage does not claim complete audit coverage of every table/operator action
or password-free/contact-free payloads in all preexisting RPC/Edge events. Auth
credential changes, direct product DML, role-permission administration, legacy
payload retention and platform access remain separate review items. No client
IP is invented from untrusted headers or the database pooler address.

Prefer forward fixes if an incompatibility appears. Keep the legacy history,
provenance column and server evidence. Never silently reenable arbitrary browser
audit insertion as a fallback. MFA remains explicitly deferred by the user.
