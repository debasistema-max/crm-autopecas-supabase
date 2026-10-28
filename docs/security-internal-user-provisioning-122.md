# Internal user provisioning - migration 122

## Status

Implemented on `codex/security-internal-user-provisioning`; controlled release
uses `codex/security-internal-users-release`. After explicit owner approval and a
fresh hash-verified backup, the original `crm-admin-users` function was deployed
and migration 122 was applied to production on 2026-10-28. All 25 database
post-application checks passed; protected existing business-data fingerprints
were unchanged in the transaction. No production user was created as a test.

The new function keeps gateway JWT verification ENABLED, in addition to its own
Auth identity, active-session and ADMIN checks. Its downloaded source matched
the tested file; six public negative/preflight checks passed. Existing deployed
functions were unchanged. MFA is deferred. Public Auth signup has NOT been
disabled or reconfigured in this stage. Frontend publication requires matching
asset hashes and updated entry-point cache versions after the reviewed PR merge.

## Security boundary

The old new-user flow invoked browser `auth.signUp` and then restored the ADMIN
session. The new flow invokes `crm-admin-users`; it never replaces that session.
Existing profile edits use UPDATE, not UPSERT. Password editing still requires
the established recovery flow; it is not silently implemented by this change.

The Edge Function verifies the allowed project/origin, Auth identity, active app
session and ADMIN permission before parsing credentials. The database independently
requires active ADMIN for preparation, and rechecks the recorded ADMIN and session
when completing the profile. Existing B2B account creation is not changed.

New internal usernames are normalized to lowercase and accept letters, digits,
period, underscore and hyphen, with length 1-80. New passwords accept 8-72
characters and are also subject to the Auth project's password policy. Existing
passwords and usernames are not migrated. All errors returned by the endpoint
are allowlisted; no request body, Auth response or provider error is logged.

## Auth and PostgreSQL are not one transaction

`internal_user_provisioning` is a private operation journal. It has RLS enabled
and no browser or service-role direct table grants. It stores actor/session IDs,
status and a temporary profile payload, never a password or token. The temporary
payload is cleared on commit/cancel. No existing user is adopted by email.

1. `prepare_internal_user_provisioning(jsonb)` is callable by authenticated
   users but requires active ADMIN. It validates the profile, checks login/email
   collisions, including existing Auth identities, and reserves a unique operation.
2. The Edge Function calls `auth.admin.createUser` using its server secret. Auth
   app metadata binds the new identity to the operation; browser metadata cannot
   supply this marker.
3. `complete_internal_user_provisioning(uuid,uuid)` is service-only. It checks
   operation, current ADMIN/session, target Auth ID/email/marker and B2B conflict,
   then atomically inserts profile, server audit and committed journal state.
4. If completion is uncertain, service-only
   `cancel_internal_user_provisioning(uuid)` locks the same journal row. It either
   returns an already committed profile, or seals cancellation before permitting
   cleanup of the exact operation-marked Auth identity without an internal profile.
   A late completion cannot create a profile after cancellation.
5. The Edge Function deletes only that marked Auth identity through the Admin API.
   `finish_internal_user_cleanup(uuid)` clears the pending-cleanup flag only after
   the identity is gone. It records a server cancellation event.

This is compensation, NOT an atomic rollback across Auth and PostgreSQL. An Auth
timeout may finish after the initial cancellation lookup, or compensation may
fail. In that case the endpoint returns a reconciliation-required error, not
success, and the journal remains available privately. It does not enumerate Auth
users or expose their passwords, hashes, tokens or account lists to the browser.

The generic profile trigger from migration 120 additionally produces its normal
BACKEND-origin profile event; the explicit CRIAR_USUARIO_INTERNO event records the
actual ADMIN from the operation. Neither event stores password/contact values.

## Tests and limitations

- Node VM tests exercise real Edge handler code with fictional Auth/RPC adapters:
  unauthorized callers, stale sessions, origins, payloads, duplicate errors,
  success, lost commit response, compensation and incomplete cleanup.
- SQL regression `supabase/tests/122_internal_user_provisioning_regression.sql`
  refuses populated/non-disposable databases. It checks actual grants/RLS,
  duplicate reservations, ADMIN and service boundaries, identity binding,
  audit rollback, cancellation ordering, idempotency and inactive-ADMIN rejection.
- The isolated schema test also reruns the actual manual/Excel/catalog SQL paths.
- On 2026-10-28 all 254 local automated tests passed, as did the real-schema SQL
  regression for provisioning and the manual/Excel/installed-catalog regressions.
  The disposable container was removed after testing; production was not contacted.
- Deno 2.5.6 type checking passed offline using the pinned existing image and the
  exact SDK version from the source. It caught a generic-client ReturnType issue;
  the ADMIN client now uses the return type of its concrete factory. No type-check
  suppression or broad `any` cast was introduced.
- The original handler then passed 35 HTTP integration checks against real
  GoTrue/PostgREST services and the full restored schema plus migrations 120-122.
  Only schema and Auth migration-version metadata were restored; all accounts and
  credentials were generated exclusively for this test.
- The service lab had an internal Docker network with no published ports. Its
  local TLS gateway owned the configured project-domain DNS alias, so the normal
  project allowlist stayed unchanged and no production/homolog server was contacted.
  Certificate verification remained enabled with a disposable local CA. All lab
  containers and the internal network were removed after testing.
- Actual HTTP checks covered ADMIN creation/session preservation, new-user login,
  seller/anonymous denial, duplicates, browser INSERT denial, service-only RPC
  denial, existing profile edits, stale sessions and logout. A dropped committed
  response was recovered without deleting the committed account. An audit failure
  compensated the new Auth identity; a forced deletion failure left a cancelled
  journal pending reconciliation, without creating a profile or claiming success.
- Public signup was disabled ONLY in the lab. Server creation still worked with
  that setting. This does not prove B2B invitation/email delivery compatibility.
- The managed Supabase Edge gateway/deployed runtime, browser and email delivery
  have NOT been tested end-to-end. The HTTP test used the unchanged handler in
  Deno CLI, not a function deployed to a Supabase project.

## Reconciliation and rollout

PREPARED operations expire for completion after ten minutes, but are deliberately
not silently freed or retried. An operator must inspect stale PREPARED and
CANCELLED/cleanup_required operations privately before retrying. Recheck Auth
using the exact operation marker, never delete a user based only on an email,
and never delete one with an existing internal profile. Keep the cancellation
tombstone so a delayed completion remains blocked. Automatic reconciliation and
journal retention scheduling are not implemented by this change.

Controlled production deployment procedure (owner approval and a fresh verified
backup are required for every application):

1. Check current schema/ACL drift and verify the Deno/isolated Auth HTTP evidence
   still matches the release sources. Those local checks passed as described above.
2. Deploy only the new endpoint, with the gateway JWT check enabled, without
   publishing the new frontend yet. Until the
   migration exists, the endpoint fails closed; the old UI is still unchanged.
3. Apply migration 122 transactionally, verify new table/RPC ACLs and existing
   profile UPDATE policies. If it fails, stop.
4. Publish cache-busted frontend promptly. Old cached ADMIN tabs using UPSERT or
   signup must refresh: migration 122 intentionally blocks direct profile INSERT.
5. Validate ADMIN creation, duplicate login/email, non-ADMIN denial, edit without
   password change and uninterrupted ADMIN session using an isolated/fake account.
6. Only after proving the new flow and B2B/invite compatibility should public Auth
   signup be disabled in a separately approved Auth configuration change.

Reference for keeping gateway verification enabled on signed-in client calls:
[Supabase authorization headers](https://supabase.com/docs/guides/functions/auth-headers).

Do not restore broad profile INSERT grants or delete journal/audit records as a
routine rollback. A frontend-only rollback to browser signup is not compatible
with the hardened insert boundary. Stop new account provisioning and keep login,
existing users and established recovery flows available while correcting it.

Remaining risks outside this stage: existing profile-email edits still do not
change the Auth email; server-side reconciliation requires operator access;
platform IAM, complete backup/Storage restoration and retention remain separate.
