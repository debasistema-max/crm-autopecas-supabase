# Product write boundary - migration 121

## Scope and status

Prepared on `codex/security-product-writes`, released through
`codex/security-product-writes-release`. Migration 121 was applied to production
on 2026-10-28 after explicit owner approval and a fresh, hash-verified backup.
All 13 post-application checks passed: browser writes/legacy delegates denied,
supported RPCs and worker access kept, RLS/policies and function bodies unchanged,
session enforcement kept. Fingerprints of protected business tables were
unchanged inside the application transaction. No real sync or customer mutation
was triggered as a test. The local automated suite passed 243 tests.

MFA remains deferred. This change does not complete the security roadmap.

The reviewed metadata exposed authenticated INSERT/UPDATE/DELETE grants on
`products` and `product_sap_data`. Table RLS still applies, but permitted
callers could write outside the approved import pipeline. The legacy
`import_products_transactional(jsonb)` RPC also allowed immediate writes by
ADMIN or an active profile with `alimentacao`. It did not require batch approval.
The raw commit delegate checked approval permission itself, but direct execution
could skip contract/branch checks performed by the current public wrapper.

## Changes

- Revoke browser-role table and column write grants on `products`,
  `product_sap_data`, `product_branch_prices`, `product_branch_stock` and
  `product_route_prices`.
- Revoke browser execution of the legacy immediate import RPC and six v0
  implementation delegates. Keep the current public wrappers unchanged.
- Fail closed in the obsolete, currently unloaded `supabase_import_fix.js`.
- Preserve SELECT grants, RLS, backend/service privileges, product records,
  favorites/recent views and ADMIN activity RPCs.
- No login, orders, quotations, fiscal calculation or active frontend layout
  changes. No cache bump: the changed obsolete script is not an entry-point asset.

## Validation evidence

The disposable PostgreSQL laboratory uses fictional users/products, has no
network or published ports, and applies migrations 118 through 121. Its SQL
regression test is `supabase/tests/121_product_write_boundary_regression.sql`.

Verified in that laboratory:

- ADMIN and seller browser roles cannot directly write protected tables.
- Legacy import and raw commit delegate execution are denied.
- Product reads remain available.
- The actual audited `set_product_active` implementation still works for ADMIN.
- An approved SECURITY DEFINER fixture writer can still update protected tables;
  a feeding-only profile cannot use it without approval permission.
- Manual inactivity survives that fixture write; repeated commits are idempotent.
- An audit failure rolls back both the fixture batch and price change.

Important: the approved writer is a test fixture, NOT the complete production
SAP commit implementation. Fiscal calculations and operational side effects in
the reduced laboratory are stubs. This does not prove full Excel/catalog/SAP
import end-to-end compatibility, nor replace browser/PostgREST testing.
Static/VM regression tests additionally check the ACL boundary, supported RPC
names, missing-batch rejection and absence of an obsolete script entry point.

### Full-schema follow-up validation (2026-10-28)

The schema-only portion of the verified 28 October backup (through migration
119) was restored in a separate disposable PostgreSQL container. Migrations
120 and 121 were then applied locally. The archive SHA-256 was verified before
extraction; no table data was extracted or restored, no passwords were restored,
and production was not contacted. The container had no network or published
ports and was removed after the test.

`supabase/tests/121_product_import_full_schema_regression.sql` exercised the
actual restored create/preview/approve/commit functions, owners, grants, RLS,
triggers and audit tables without replacing their bodies. All assertions passed:

- ADMIN validated, previewed, approved and committed a two-product batch.
- One existing price and one new product were saved; fields absent from the
  payload and manual inactivity were preserved.
- Empty code/description, zero/negative price, negative stock and duplicate codes
  produced blocking errors. A 90% price reduction produced a nonblocking warning.
- A feeding-only supervisor could validate but could not approve, commit, call
  the raw delegate or update a product directly. A seller without feeding
  permission could not validate or call the obsolete import RPC.
- Field audit stored the actual previous/new price, and the final log was stamped
  SERVER. Repeated file/commit attempts were rejected without duplicate audit.
- A deliberately failing audit trigger rolled back product changes, audit rows
  and batch status in the actual commit implementation.

This closes the earlier representative-writer limitation for the manual v0 SAP
import path. Live schema drift after the source backup must still be checked
before a production migration. No current backup has been certified as a complete
disaster-recovery restoration by this schema-only test.

### Real integration write paths (2026-10-28)

`supabase/tests/121_product_integrations_regression.sql` also passed on the full
restored schema with migrations 120 and 121 applied, without replacing RPCs:

- The actual `service_role` ran create/stage/validate/chunked-commit for an Excel
  batch, saving a product, SAP metadata, zero stock, branch base price and route
  price. Absent/empty fields and manual inactivity were preserved.
- A repeated chunk commit did not duplicate audit rows; repeating the same
  source/file identity returned the original batch.
- An authenticated ADMIN requested installed-catalog synchronization. Execution
  then switched to the real dedicated `ips_catalog_worker` session role, not the
  database owner, for claim/snapshot/finish.
- A wrong claim token was rejected. Browser roles could not call the worker
  claim/finish RPCs, and the worker could not update products directly.
- Catalog changes preserved prices, inactivity and manual notes. Repeated finish
  calls did not duplicate catalog audit or SERVER log events.

These are database integration tests, not a full end-to-end service drill. The
actual OneDrive file, installed catalog package, private runner, GoTrue,
PostgREST, Edge HTTP endpoints and browser were not executed. No real
synchronization was requested or run in production.

## Controlled deployment prerequisites

1. Obtain explicit production approval. Confirm the pinned project, current
   migration state and an up-to-date ACL/function inventory; review any drift.
2. Generate and verify a fresh backup. Preserve pre-migration ACLs privately for
   recovery; do not commit dumps, credentials or private metadata.
3. Manual SAP and Excel/catalog database write paths passed the full-schema
   fictional-data tests above. Validate the HTTP/service/browser entry points
   and B2B reads separately; those complete end-to-end integrations were not
   covered by the SQL tests. Do not trigger a real production sync as a test.
4. Apply only migration 121 transactionally. If it fails, stop. Check table AND
   column grants, current wrapper execution, raw delegate denial and RLS state.
5. Publish only the reviewed files, without force push. Recheck product reads,
   ADMIN activity changes and approved import behavior. Do not mutate real
   customer documents as a test.

The migration does not erase data and is transactional. An unexpected integration
using direct browser writes or the obsolete RPC will fail after application.
Do not restore broad browser write grants as a routine rollback. Prefer fixing
the approved path; any emergency privilege recovery requires explicit approval
and comparison with the saved ACL inventory.

## Remaining security work

- Move internal account provisioning out of browser `auth.signUp` to an
  ADMIN-authorized server endpoint, with compensation/reconciliation for a
  partial Auth/profile failure. Only then evaluate disabling public signup.
- Complete full isolated authorization tests for ADMIN, two sellers and B2B.
- Prove restoration of current backups, including Auth and Storage files.
- Review platform administrators/tokens and data/log/attachment retention.
- Revisit ADMIN MFA separately when the owner is ready.
