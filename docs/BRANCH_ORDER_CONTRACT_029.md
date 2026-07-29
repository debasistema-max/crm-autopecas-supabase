# Migration 029 - Branch Order Contract

## Objective

Migration 029 introduces only the structural contract needed to associate orders
and quotations with branches. It prepares migrations 030 and 031 without
reserving stock, changing balances, creating stock movements, or replacing
commercial RPCs.

**Migration 029 does not enable V1 orders.**

## Scope

The migration changes only the database contract for:

- `orders`
- `order_items`
- `quotations`
- `quotation_items`
- the internal singleton `order_stock_contract_settings`

It does not change frontend code, Auth, Storage, Edge Functions, secrets,
products, branch stock, branch prices, stock movements, or import contracts.

## Pre-audit

The repository and a validated production backup restored in PostgreSQL 17.6
were audited before implementation.

| Area | Result |
| --- | --- |
| Orders | UUID PK; `regiao order_region NOT NULL DEFAULT 'SP'`; status enum `NOVO`, `EM_ANALISE`, `APROVADO`, `CANCELADO`, `FATURADO` |
| Order items | UUID PK; FK to orders; canonical product key is `codigo`; existing uniqueness is `(order_id, item)` |
| Quotations | UUID PK; `regiao order_region NOT NULL DEFAULT 'SP'`; status enum `NOVA`, `ENVIADA`, `APROVADA`, `CANCELADA`, `CONVERTIDA` |
| Quotation items | UUID PK; FK to quotations; canonical product key is `codigo`; existing uniqueness is `(quotation_id, item)` |
| Commercial RPCs | Migration 025 security-definer RPCs create/update documents from `regiao`; direct authenticated table writes are not granted |
| RLS before 029 | ADMIN or owner reads orders/quotations; items follow their parent; table grants are SELECT-only |
| Triggers | `orders_touch_updated_at`, `quotations_touch_updated_at`, and commercial timeline triggers exist |
| Branches | `PR` and `SP` are active; `PR` is the single headquarters |
| User branches | `profile_branches` supports active, default, multi-branch links |
| Company settings | Existing public singleton is dedicated to white-label identity |
| Restored operational data | 0 orders, 0 order items, 0 quotations, 0 quotation items |
| Duplicate products | None found |
| Regions found | No operational rows; schema only permits `PR` and `SP` and currently rejects NULL |
| Unmappable rows | None |

The feature flag was deliberately kept out of `company_settings`. White-label
identity and operational rollout controls have different ownership and
exposure requirements.

## V0 contract

Current and historical documents remain:

```text
stock_contract_version = 0
orders.logistics_status = LEGACY_UNMANAGED
operational_version = 0
priority = NULL
promised_at = NULL
```

`regiao` is preserved. Migration backfill resolves active `PR` and `SP`
branches and writes `branch_id` without changing the contract version. Current
commercial RPCs omit the new columns and therefore continue creating V0
documents. An internal trigger resolves their V0 branch from `regiao`.

V0 creates no reservations, events specific to this contract, or stock
movements.

## V1 contract

The structure supports a future V1 document with:

- `branch_id` required;
- non-legacy logistics status for orders;
- priority required;
- coherent branch-price snapshots on every item;
- non-negative operational version.

V1 creation is rejected while
`order_stock_contract_v1_enabled = false`. Migration 031 will own controlled
activation and commercial RPC integration.

## Columns

### orders

- `branch_id uuid`
- `stock_contract_version smallint NOT NULL DEFAULT 0`
- `logistics_status text NOT NULL DEFAULT 'LEGACY_UNMANAGED'`
- `priority text`
- `promised_at timestamptz`
- `operational_version bigint NOT NULL DEFAULT 0`
- `branch_locked_at timestamptz`
- `approval_requested_at timestamptz`
- `price_revalidation_required_at timestamptz`

The table already has `created_at` and `updated_at`, so no duplicate timestamp
metadata was added.

### quotations

- `branch_id uuid`
- `stock_contract_version smallint NOT NULL DEFAULT 0`
- `priority text`
- `promised_at timestamptz`
- `operational_version bigint NOT NULL DEFAULT 0`

Priority and promise are included so a future quotation-to-order conversion can
preserve both.

### order_items and quotation_items

- `branch_price numeric(14,4)`
- `branch_price_currency character(3)`
- `branch_price_version bigint`
- `branch_price_captured_at timestamptz`

These fields complement existing commercial prices. They do not replace
`preco_unitario`, `preco_final_unitario`, or `total_item`.

## States and priorities

Closed logistics values:

```text
LEGACY_UNMANAGED
DRAFT
READY_FOR_APPROVAL
AWAITING_STOCK
RESERVED
CONSUMED
CANCELLED
```

Closed priority values:

```text
LOW
NORMAL
HIGH
URGENT
```

Text checks were preferred to PostgreSQL enums so later state evolution and a
pre-operational rollback remain manageable.

## Backfill

Before any update, migration 029:

1. validates the required 027/028 tables;
2. validates exactly one active canonical PR headquarters and one active SP
   branch;
3. blocks non-null regions without an active branch mapping;
4. blocks repeated canonical product codes within a document.

The branch table is held with a share lock and the four commercial tables with
share-row-exclusive locks from preflight through commit. Concurrent branch or
document writes therefore cannot invalidate the audit before backfill.

Only after the complete preflight passes are `branch_id` values populated.
There is no partial backfill. A defensive NULL-region path leaves `branch_id`
NULL and V0 unchanged, although the current schema makes `regiao` NOT NULL.
The migration temporarily disables only the two legacy `touch_updated_at`
triggers during this structural backfill, restores them immediately, and
verifies that historical `updated_at` values remain byte-for-byte unchanged.

## Feature flag

`order_stock_contract_settings` is a dedicated singleton containing:

```text
order_stock_contract_v1_enabled = false
```

RLS allows only ADMIN to read it. `authenticated` receives no INSERT, UPDATE,
or DELETE grant, including ADMIN sessions. Migration 029 exposes no activation
RPC. A future controlled ADMIN RPC belongs to migration 031.

## Constraints

The migration validates:

- contract version 0 or 1;
- closed logistics and priority values;
- non-negative operational version;
- V0 legacy-only logistics and empty future operational metadata;
- required branch, non-legacy logistics, and priority for V1;
- coherent dates;
- all-null or complete branch-price snapshots;
- non-negative price, uppercase ISO-like currency, and positive price version;
- snapshot parent contract matching;
- one canonical product code per order or quotation.

Checks and FKs are added `NOT VALID` and then explicitly validated. Unique
indexes are created only after the duplicate preflight succeeds.

## Indexes

- unique `(order_id, codigo)` and `(quotation_id, codigo)` prevent duplicate
  canonical products;
- partial branch/logistics and branch/priority indexes serve future V1 queues;
- partial owner/branch indexes serve scoped V1 document lists;
- quotation equivalents serve branch and owner lists.

All operational indexes are partial on `stock_contract_version = 1`, avoiding
unnecessary V0 index volume.

## RLS and grants

V0 read behavior is unchanged: ADMIN reads globally and other profiles read
their own documents.

For dormant V1 rows:

- ADMIN reads globally;
- SUPERVISOR reads documents in linked active branches;
- VENDEDOR reads only own documents in linked active branches;
- inactive profiles read no V1 documents;
- item visibility follows the parent document.

The rewritten policies split V0 and V1 explicitly, preventing permissive-policy
OR composition from broadening V0. Existing SELECT-only table grants are
preserved. `anon` and `PUBLIC` receive no new access.

## Rollback

The rollback is transactional, has no `CASCADE`, restores the four migration
025 read policies, and removes only 029 objects.

It blocks before dismantling if any of these conditions exists:

- a migration version greater than 029 is registered;
- the feature flag is enabled;
- any V1 order or quotation exists;
- any order uses non-legacy logistics;
- any branch-price snapshot is populated.

Rollback is supported only before operational V1 use.

## Reapplication

The migration can be reapplied only in the pre-operational window. Reapplication
is blocked by downstream migrations, enabled V1, V1 rows, operational
logistics, or used snapshots. It must never be repaired or edited after remote
application.

## Tests

`supabase/tests/029_branch_order_contract_validation.sql` is transactional and
covers:

- first application, second pre-operational application, successful rollback,
  and a final application through relative `psql` includes;
- feature flag singleton and grants;
- required columns;
- V0 defaults and PR/SP branch resolution;
- disabled V1 rejection;
- V0/V1 coherence;
- valid and invalid priorities;
- complete and incomplete snapshots;
- duplicate order and quotation products;
- ADMIN, SUPERVISOR, VENDEDOR, and anon access;
- direct feature-flag write denial;
- 028 advisory lock markers;
- unchanged 027/028 function fingerprints, stock, reservations, movements, and
  branch prices.

Run the suite only on a disposable PostgreSQL 17.6 server. The source database
must be restored through migration 028 and the runner must be allowed to create
and drop temporary databases. Run from the `supabase` directory in the
PostgreSQL container or another POSIX-shell test environment:

```text
psql -v ON_ERROR_STOP=1 -f tests/029_branch_order_contract_validation.sql
```

The suite creates uniquely named database clones for NULL and unmappable-region
fixtures, duplicate products, rollback blocking by V1, rollback blocking by a
simulated version 030, and reapplication blocking after operational use.
Expected migration failures run in isolated `psql` subprocesses. Each negative
test requires both a nonzero process status and its exact controlled error code,
then performs a structural assertion. All clones are force-dropped after a
successful run. If the suite is interrupted, remove databases whose names start
with `test029_` before re-running it.

## Risks and limitations

- Adding unique product indexes will intentionally block deployment if legacy
  duplicates appear after this audit.
- `regiao` remains the legacy SP/PR enum; migration 031 must define how new
  branch codes coexist with that compatibility field.
- No workflow transition, approval, reservation, shortage, or withdrawal logic
  is implemented here.
- Priority and promise permissions are documented but remain unenforced until
  controlled V1 write RPCs exist.
- Reapplication and rollback assume the migration history is authoritative.
  Unregistered manual rewrites of the four commercial read policies are not
  fingerprinted and must be reconciled before running either file.
- A manually created partial 029 schema can fail with a generic missing-column
  error. Recover such an environment from a clean 028 restore instead of using
  migration repair.
- Migration 030 will add reservations and evidence of stock attempts.
- Migration 031 will integrate commercial RPCs and may activate V1 only after
  explicit validation.

## Acceptance criteria

- all existing documents remain V0;
- every safely mappable V0 document receives the canonical branch;
- V1 remains disabled and cannot be created;
- no stock, reservation, movement, event, or import object changes;
- role reads do not broaden V0 access;
- rollback succeeds only before operational use;
- migrations 027 and 028 remain unchanged.
