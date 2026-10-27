# Security hardening - stage 1: portfolio boundary

Status: migration 118 applied to production on 2026-10-27 after explicit user
authorization and a new verified backup. Independent read-only postflight passed.
Frontend deployment was not needed. Source changes remain on the branch below.
Branch: `codex/security-portfolio-rpc`.

## Scope

Migration `118_document_portfolio_boundary.sql` closes the audit's high-severity
creation bypass without changing frontend APIs, fiscal rules, tables or records.

- The shared `commercial_create_document(text,jsonb)` validates portfolio scope
  before invoking the existing transactional pricing and creation pipeline.
- SAP code, normalized CNPJ and optional client ID must describe the same active
  client assigned to the active seller. Unknown and conflicting identifiers fail
  with the same existing business error, without exposing customer details.
- The client row is locked with `FOR SHARE` until the transaction ends, preventing
  concurrent reassignment/deactivation between authorization and creation.
- Anonymous quotations remain supported; anonymous seller orders do not.
- Conversion checks the saved quotation owner and its current portfolio client
  before invoking the existing snapshot copier. Old quotations linked outside
  the current portfolio cannot create new seller orders through conversion.
- ADMIN retains its existing workflow. Creation permissions and server pricing
  remain enforced by the existing downstream implementations.
- Internal delegates, the guard and the finalizer remain non-executable by
  PUBLIC, anon and authenticated.

No existing document is rewritten. Legacy cross-portfolio quotations may now be
blocked on conversion; ADMIN must review those cases rather than bypassing the
guard for the seller. B2B creation has a separate implementation and was not
modified; this is not a complete B2B end-to-end certification.

## Validation

- `npm test`: includes static boundary contracts and the existing CRM suite.
- `supabase/tests/118_document_portfolio_boundary_regression.sql`: only for the
  fictional authorization fixture in a disposable database. It refuses to run
  unless `crm.test_disposable` is explicitly `on` and rolls back its test changes.
- The isolated fixture uses the audited migration-117 creation/conversion bodies
  and current authorization policies, with fictional profiles, clients and
  products. Fiscal/operational services are stubs; no real backup is loaded.
- Cases: own generic/wrapper creation, foreign SAP/CNPJ, conflicting identifiers,
  explicit foreign ID, missing/inactive client, missing creation permission,
  anonymous quotation/order, invalid input, ADMIN, inactive profile, no partial
  documents, valid/idempotent conversion and rejected legacy foreign conversion.
- Tests use network-disabled PostgreSQL with no published ports. Private audit
  metadata and execution logs must not be committed or published.

## Controlled rollout

Production execution: backup verified at approximately 30.5 MB (custom-format
PostgreSQL dump), with password-free role export, readable TOC and SHA-256 hashes.
Migration and migration-history registration committed atomically at 17:41 UTC
on 2026-10-27. Postflight verified the guard, conversion ownership/client checks,
internal helper ACLs and unchanged RLS/table grants. No production test records
were created. Backup restore and Storage object-body recovery were not tested
as part of this deployment. Private manifests are retained outside Git.

1. Review the diff; confirm target environment and migrations through 117.
2. Keep production unchanged until explicit deployment authorization. Hosted
   homologation was unavailable at audit time; do not bypass that failure by
   testing mutations in production.
3. Complete isolated tests and, when available, homologation with two fictional
   sellers and an ADMIN. Validate the actual fiscal pipeline and full UI there.
4. Before a production change, make a fresh verified backup and preserve the
   current definitions/ACLs of the affected functions privately.
5. Apply only migration 118 using the established targeted migration procedure.
   Do not reset the database or indiscriminately push historical migrations.
6. Read back function definitions/ACLs; confirm the shared guard precedes writes
   and internal helpers remain inaccessible. Record the migration in the normal
   migration history. No frontend deployment is needed for this SQL-only fix.
7. Monitor authorization errors without logging request credentials or customer
   payloads. Existing business errors remain compatible with the frontend.

The migration is transactional. If it fails, stop and investigate; do not
partially apply statements. After successful application, prefer a forward fix.
Do not restore the vulnerable generic creation definition as a rollback. If a
regression requires containment, suspend affected creation/conversion entry
points through an explicitly approved change while retaining read access.

## Remaining audit stages

This stage does not resolve MFA/AAL2, user password administration, confidential
client columns, CSV formula handling, trusted audit events, public signup,
product write privileges or complete recovery of the current version. Each
requires a separately reviewed change and regression tests. MFA enrollment and
platform IAM review also require the account owners; never request secret values
in chat. Do not describe production as remediated until the migration is applied
and the remaining findings are addressed.
