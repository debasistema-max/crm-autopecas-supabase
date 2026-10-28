# Client commercial field boundary - migration 119

Status: local preparation only. No production/homologation migration, frontend
publication, real customer mutation or credential change in this stage.
Branch: `codex/security-client-fields`. MFA remains deferred.

## Scope and permissions

The audit found that `clients_read` restricts a seller's rows, but a table-wide
SELECT still exposes `commercial_discount_percent` on those rows. Hiding the
field in the UI or returning null in a list RPC does not close direct API access.

Migration 119 replaces the authenticated role's table-wide SELECT with an
explicit column allowlist excluding the discount, and explicitly revokes any
discount-column SELECT from PUBLIC, anon and authenticated. It does not drop
data, disable RLS, change portfolio policies or grant broader write privileges.
New columns are not automatically exposed by the allowlist.

All browser identities use the same PostgreSQL authenticated role. Therefore
ADMIN also loses direct SELECT of the discount, intentionally. Privileged UI
reads and saves use authorized SECURITY DEFINER RPCs with a fixed search_path.
Database administrators and trusted server identities are not restricted as if
they were salespeople.

- VENDEDOR: ordinary direct SELECT remains RLS-scoped to the seller's portfolio.
  Direct discount SELECT, filter, ordering, aggregation and whole-row queries
  fail. The existing list RPC keeps returning a null discount, while the new
  exact lookup omits the key completely. Client writes remain denied.
- ADMIN: can read and save commercial fields through the scoped RPCs.
- Other internal staff: preserve the existing `parceiros` permission requirement
  for the new management RPCs. They may save ordinary client fields, but changing
  the discount requires ADMIN. The existing discount trigger is preserved.
- Inactive profiles, replaced/inactive app sessions, identities without an
  internal profile and anonymous callers cannot use the new RPCs.

## RPCs and frontend

`find_business_client_scoped(lookup_field text,lookup_value text)` only accepts
exact SAP-code or CNPJ lookup, with normalized CNPJ input. Portfolio filtering
occurs before returning a result. It does not accept arbitrary SQL, fields,
discount filters or a browser-supplied role. Missing/out-of-scope clients return
null. Authorized staff retain the discount needed when promoting a portal
registration without resetting its existing commercial settings.

`save_business_client_scoped(payload jsonb)` replaces the browser's direct
upsert-and-select. It validates the active actor/session, staff permission,
mandatory name, email, finite/nonnegative discount within the current limit and
newly assigned active salesperson. An unchanged legacy assignment is preserved,
even if its salesperson later became inactive. It serializes same-ID upserts and locks an existing
row before checking changes to the discount. The client save and SALVAR_CLIENTE
event share one transaction. Audit failure aborts the save.

The event uses the server-derived actor, discount/assignment before and after,
and changed-field names. It does not duplicate contact values in the new event.
This makes this RPC's own event authoritative, but does NOT fix the separate
audit finding that other client code can append fabricated events to `logs`.

The frontend uses the two RPCs without falling back to direct sensitive reads.
Existing list/search functions and the order/quotation APIs remain unchanged.
Invalid numeric input is rejected before sending; the server independently
enforces its own validations. Store cache-bust is updated in both entry points.

## Validation

- Final result on 2026-10-27: 227 tests passed (120 static/UI contracts, 63
  session/document/security tests and 44 Python tests). Syntax, migration
  sequence and diff checks passed. The migration-119 disposable SQL regression
  also passed, including replaced sessions and unchanged inactive assignments.
- Full CRM suite via `npm test`, including `client-field-security.test.cjs`.
- `supabase/tests/119_client_commercial_field_boundary_regression.sql` runs only
  on a disposable fictional fixture with `crm.test_disposable=on`, and rolls back.
- Isolated PostgreSQL has no network or published ports, and uses no customer
  backup/data. It loads the audited session/role/RLS helpers and both migrations
  118 and 119 over synthetic tables. Operational/fiscal services are stubs.
- Cases: direct secret reads and inference queries, ordinary own-client reads,
  foreign lookup, masked lists, seller write attempts, ADMIN save/read, authorized
  staff unchanged-discount save, staff discount rejection, limits/nonfinite
  values, inactive/replaced sessions, missing profile, anon ACL and audit rollback.
- Frontend mocks cover normalized RPC payloads, errors without unsafe fallback,
  portal promotion preserving an existing discount/seller and invalid input.

These are not complete browser, PostgREST or B2B/fiscal end-to-end tests. RLS and
SECURITY DEFINER configuration in production must be read back at rollout time;
passing local tests does not prove the hosted database is already protected.

## Controlled rollout (requires separate authorization)

1. Review the migration, take a fresh verified backup, and confirm production is
   at migration 118 with the expected functions, policies and grants.
2. Validate in isolated/recovered homologation. Check client editing, portal
   promotion, lookup, order/quotation selection and B2B pricing with fictional data.
3. Coordinate migration 119 and this frontend release in a short maintenance
   window. Apply the migration before publishing its frontend; do not publish
   RPC-dependent frontend against a database missing those functions.
4. Existing ADMIN tabs using old direct upsert-returning-discount will fail after
   the grant change until refreshed. Advise staff to save pending edits first,
   then reopen/refresh after publication. A failed permission check does not
   authorize a fallback to the old query. Seller list RPCs remain compatible.
5. Read back column privileges, RPC ACLs, session checks and unchanged RLS.
   Confirm ADMIN works via RPC, seller cannot read/filter the secret, saved
   clients keep their settings, and audit is emitted once. No real cross-user
   tests or fixture creation in production.
6. Verify public asset hashes/cache versions and monitor safe error metadata.

The migration is transactional and must stop/roll back on failure. Prefer a
forward fix if rollout exposes a compatibility issue. Do not restore table-wide
SELECT as an automatic rollback: it reopens the confirmed vulnerability. The
current frontend release remains unchanged until explicit rollout authorization.

## Remaining limits

This protects the structured internal discount, not arbitrary confidential text
someone may type into names/notes, nor inferences from prices legitimately shown
to a customer. Existing historical logs, log-read permissions and trusted audit
insertion need their separate audit stage. Product DML, Auth provisioning,
current full-system recovery and MFA remain outside this change.
