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

### Document/item locking

Every V0/V1 transition first acquires the transaction-scoped advisory lock
`(29, 0)` through a `BEFORE STATEMENT` trigger, before any target row lock can
be taken. Relevant item updates acquire the lock through their own
`BEFORE STATEMENT` triggers, which also protects multi-row updates. Item
inserts acquire the lock through `BEFORE STATEMENT` as well, preventing a
multi-row insert from locking a V0 parent before a later snapshot row.

Before an item insert or relevant update reads the parent contract, its row
trigger then locks the parent with `FOR NO KEY UPDATE`. If an update moves an
item, both old and new parents are locked in ascending UUID order.

A parent transition already owns the same row-level lock as part of its update.
For transitions and relevant item updates the order is advisory lock, target
rows, parent document rows in ascending UUID order, validation, then write.
For item inserts with snapshots there is no pre-existing item row, so the row
trigger acquires the advisory lock before the parent lock.

The contract-wide lock prevents opposite multi-document and mixed
order/quotation contract operations from entering the parent-lock phase in
conflicting orders. Parent row locks provide document-level serialization and
guarantee that item validation cannot observe a stale contract. V0 document
writes and unrelated updates remain concurrent; item INSERT statements are
intentionally serialized because PostgreSQL cannot inspect all proposed rows
before the first row lock. The advisory key is a fixed integer pair, not a
hash, so there is no application-level collision ambiguity.

The legacy item-update and quotation-conversion RPCs acquire `(29, 0)`
unconditionally before their first document `FOR UPDATE`. Both can write item
rows, so a V0-only shortcut would invert the order against the statement
triggers during a concurrent V0/V1 transition. Future RPCs that can write items
or snapshots must follow the same rule, and RPCs that lock several parent
documents must preserve ascending UUID order. Privileged maintenance SQL must
explicitly acquire `(29, 0)` before pre-locking a document when the transaction
will also write items, change a contract version, or change a snapshot.

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
2. validates every pre-existing 029 column, constraint, and index against an
   independently built temporary contract model;
3. validates exactly one active canonical PR headquarters and one active SP
   branch;
4. blocks non-null regions without an active branch mapping;
5. blocks repeated canonical product codes within a document.

The global migration lock order is:

1. `supabase_migrations.schema_migrations` in `SHARE` mode, when present;
2. `branches` in `SHARE` mode;
3. orders, order items, quotations, and quotation items in
   `SHARE ROW EXCLUSIVE` mode;
4. the existing feature-flag table in `SHARE ROW EXCLUSIVE` mode.

These locks are held from preflight through commit. Concurrent history,
branch, document, item, or feature-flag writes therefore cannot invalidate the
audit before backfill. Operational guards only inspect an existing 029 column
after its primitive type is known to be compatible; all other drift is rejected
by the complete structural fingerprint with a controlled diagnostic.

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

Existing objects are never trusted by name alone. Column fingerprints include
type OID and modifier, nullability, default, identity, generated state, and
collation. Constraint fingerprints include type, validation and deferrability
state, expression, referenced columns, and complete catalog definition. Index
fingerprints include owning table, uniqueness, primary/exclusion flags,
valid/ready/live state, access method, keys, ordering, opclasses, INCLUDE
columns, expressions, and partial predicate. A mismatch aborts the transaction
with a dedicated `MIGRATION_029_*_FINGERPRINT_MISMATCH` error whose detail
contains the object plus expected and actual fingerprints.

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

Before replacing the four migration 025 read policies, the migration creates
transaction-local comparison policies on the same relations and compares the
catalog trees for command, roles, permissiveness, `USING`, and `WITH CHECK`.
The six existing insert/update policies receive the same comparison. Any
missing or divergent legacy policy aborts the migration; the rollback's
deterministic definitions are therefore exact for every accepted baseline.

The preflight also requires RLS enabled without `FORCE ROW LEVEL SECURITY`,
the exact ten migration 025 commercial policy definitions, the exact normalized
table ACL, no column ACLs, SELECT-only access for `authenticated`, no commercial
table access for `anon`/`PUBLIC`, no direct authenticated writes, and the
expected table owner. Extra roles, policies, disabled RLS, or broader
table/column grants abort before persistent 029 changes.

## Rollback

The rollback is transactional, has no `CASCADE`, restores the four migration
025 read policies and the exact pre-029 definitions of the three commercial
RPCs touched by the lock protocol, then removes only 029 objects and snapshot
rows. It locks migration history first, then orders, order items, quotations,
and quotation items in
share-row-exclusive mode, followed by the settings singleton table when
present. All usage checks run only after these locks are held, closing both the
history and commercial preflight/write TOCTOU windows.

Before dropping any object, the rollback verifies one immutable catalog
manifest covering all 029 functions, indexes, constraints, triggers, columns,
policies, relation metadata, owners, RLS flags, table/column ACLs, function
ACLs, and function configuration. A missing, substituted, or altered object
aborts with `ROLLBACK_029_OBJECT_FINGERPRINT_MISMATCH`; no partial teardown is
allowed.

It blocks before dismantling if any of these conditions exists:

- a migration version greater than 029 is registered;
- the feature flag is enabled;
- any V1 order or quotation exists;
- any order uses non-legacy logistics;
- any branch-price snapshot is populated.

Rollback is supported only before operational V1 use.

A second rollback execution is explicitly supported. Missing settings are
accepted only when every reserved 029 function, column, index, constraint, and
trigger is absent and the four legacy read policies plus three commercial RPCs
match their immutable 028 fingerprints. A partial state without settings
aborts with `ROLLBACK_029_PARTIAL_STATE_WITHOUT_SETTINGS`; a divergent legacy
baseline aborts separately. A clean second execution restores the 025 read
policies deterministically again.

## Reapplication

The migration is single-application by design. A second invocation, including
the pre-operational window, aborts atomically with
`MIGRATION_029_ALREADY_APPLIED_OR_PARTIAL`. Operational and downstream guards
run first so their more specific diagnostics remain available. This removes
all reliance on a self-declared reapplication marker and prevents forged
snapshot rows from becoming rollback input. It must never be repaired, edited,
or reapplied after remote application.

On first application, homonymous columns, constraints, indexes, policies,
legacy timestamp triggers, or snapshot-storage objects with a different
identity abort before any persistent 029 change. Snapshot storage is locked
before inspection; table kind, RLS state, columns, constraints, backing
indexes, owner, grants, policies, and user triggers are validated.
Homonymous 029 helper functions are treated as partial installation and are
never overwritten. All reserved 029 trigger names are rejected before the
first `DROP TRIGGER`, including compatibility names not recreated by the final
migration.

## Tests

`supabase/tests/029_branch_order_contract_validation.sql` is clone-isolated and
covers:

- first application, controlled rejection of a second application, successful
  rollback, repeated rollback, and relative `psql` includes;
- feature flag singleton and grants;
- required columns;
- incompatible homonymous column, constraint, and index rejection;
- V0 defaults and PR/SP branch resolution;
- disabled V1 rejection;
- V0/V1 coherence;
- valid and invalid priorities;
- complete and incomplete snapshots;
- duplicate order and quotation products;
- ADMIN, SUPERVISOR, VENDEDOR, and anon access;
- direct feature-flag write denial and real INSERT/UPDATE/DELETE denial on all
  four commercial tables for ADMIN, SUPERVISOR, and VENDEDOR sessions;
- concurrent item-first and parent-first order transitions;
- concurrent item-first and parent-first quotation transitions;
- concurrent opposite-direction item moves between two parents, proving the
  ascending UUID lock order and absence of SQLSTATE `40P01`;
- a mixed multi-row INSERT containing a V0 item without snapshots and a V1 item
  with snapshots while the V0 parent transitions concurrently;
- mixed order/quotation contract updates in opposite order, plus concurrent V0
  writes on unrelated documents proving they are not globally serialized;
- real `commercial_update_document_items` and
  `convert_quotation_to_order` calls blocked behind the protocol lock before
  their document row locks, with explicit rejection of SQLSTATE `40P01`;
- deterministic two-way test barriers: a FIFO keeps the first transaction
  open, an advisory marker proves it owns the document protocol, and
  `pg_stat_activity` proves the competing session is waiting on a lock before
  the first transaction is released;
- isolated guards for active flag, quotation V1, snapshots, operational
  version, logistics use, and downstream migration;
- 028 advisory lock markers;
- exact SQLSTATE plus constraint or controlled trigger message for negative
  assertions;
- exact restoration of the four migration 025 policies before a fresh
  post-rollback application;
- forged reapplication-marker rejection, legacy policy adulteration rejection,
  disabled-RLS/extra-policy/table-or-column-grant rejection,
  homonymous-helper rejection, snapshot `TRUNCATE`/column-grant/extra-constraint
  rejection, reserved-trigger rejection, partial-state-without-settings
  rejection, settings PK/check/trigger fingerprinting, unrelated `_029` object
  tolerance, substituted rollback-object rejection, and altered legacy-RPC ACL
  rejection,
  and rejection of a syntactically valid, self-consistent but non-baseline RPC
  snapshot;
- a temporary authenticated `UPDATE` grant proving that RLS itself rejects a
  non-owner write, independently from the normal no-write table grants;
- exact definition, owner, ACL, and configuration restoration for legacy
  commercial RPCs through validated 028 snapshot storage plus immutable
  baseline definition, owner, ACL, and `search_path` anchors in the migration
  and rollback SQL;
- unchanged 027/028 rows and individual catalog fingerprints for `products`,
  branches, profile links, stock, prices, movements, all import batch/staging/
  audit tables, legacy snapshot tables, constraints, indexes, triggers,
  policies, RLS/forced-RLS flags, owners, table and column ACLs, `pgcrypto`,
  and function definitions.

Run the suite only on a disposable PostgreSQL 17.6 server. The source database
must be restored through migration 028 and the runner must be allowed to create
and drop temporary databases. Run from the `supabase` directory in the
PostgreSQL container or another POSIX-shell test environment:

```text
psql -v ON_ERROR_STOP=1 -f tests/029_branch_order_contract_validation.sql
```

The suite creates a disposable main clone plus uniquely named databases for
NULL and unmappable-region fixtures, duplicate products, structural
adulteration, concurrency, isolated rollback/reapplication guards, simulated
version 030, and operational V1 use. The source restored at migration 028 is
never migrated and is verified again at the end.
Expected migration failures run in isolated `psql` subprocesses. Each negative
test requires both a nonzero process status and its exact controlled error code,
constraint name or object-specific trigger message, then performs a state
assertion. The outer runner installs an `EXIT`, `INT`, and `TERM` cleanup trap;
all clones for its unique run token are force-dropped after success, failure,
or interruption. Full schema-only and data-only `pg_dump` SHA-256 fingerprints
of the source are compared before and after every run. The schema fingerprint
retains ownership and privilege statements, so owner and ACL drift is visible;
the data fingerprint intentionally omits ownership metadata. The wrapper uses
Bash `pipefail` and rejects any failed dump or hash stage. The source database
remains at migration 028 throughout.

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
- Structural fingerprints deliberately cover 029 columns, constraints, and
  indexes. Manual drift in unrelated objects still requires reconciliation from
  a clean, validated backup.
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
