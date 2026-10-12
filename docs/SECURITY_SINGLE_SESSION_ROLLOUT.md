# Security single-session rollout

## Scope and evidence

This is a local deployment/hardening plan, not evidence of completed remote
actions. The parent session owns implementation and coordinates one approved
revision. Do not start competing sessions, change architecture, or add features.
Follow [AGENTS.md](../AGENTS.md), [deployment.md](deployment.md), and
[testing.md](testing.md). Production mutations require explicit authorization;
validate in homologacao first. Never put credentials, dumps, or personal data in
Git, public artifacts, or logs.

Local inspection found an ungated Pages deploy, pinned checkout/setup-python in
`security.yml`, Python requirements in `scripts/requirements-data-sync.txt`, and
no `.github/dependabot.yml`. Historical audit claims are not current remote
verification. This checkout has no `pgdump` workflow or `supabase/config.toml`;
inspect the existing remote backup and function settings rather than inventing
their configuration.

Parent-reported evidence on 2026-10-12 (not independently verified here):
foundation SQL 100 compiled and its homologacao regression passed with `ROLLBACK`
for takeover, replay, release, RLS, API, scheduler and grants. The parent also
reported a successful 303 MB production `pg_dump` at 09:32 on 2026-10-12. Confirm
the backup's exact location, timezone, checksum and restore verification before
mutation; neither report establishes production activation of migration 103.
The parent subsequently reported 100/101 already applied in homologacao; preserve
both immutable. Review through homologacao tests remains staged with
`app_session_policy.enforced=false`, not activated. Following seed/claim race
review, new forward migration 102 adds the monotonic claim guard and the local,
unapplied activation file moved to 103. These reports are not independent remote
verification by this session.

## Pages gate

`static.yml` now runs `Deploy regression` before any Pages setup, upload, or
deploy. It installs Python requirements, runs `npm run check` (migration sequence
and JavaScript syntax), `npm run test:static`, and `npm run test:python`.
It also explicitly runs `node --test tests/single-session-frontend.test.cjs`
before deploy; this covers the standalone mocked session/login regressions.
`deploy` has `needs: regression` with normal success semantics: failure, timeout,
or cancellation blocks deployment. No `always()` or `continue-on-error` bypass.
Both jobs check out the same workflow revision; no mutable ref override is used.

The regression token has only `contents: read`. Existing workflow permissions,
push-to-main/manual triggers (no dispatch inputs), `pages` concurrency with
cancellation, `github-pages` environment/URL, public artifact path, and deploy
timeout remain unchanged. Node/npm use the Ubuntu runner, matching `security.yml`;
there are no npm dependencies needed by these checks. Official actions use full
commit pins; checkout and setup-python exactly match `security.yml`. Pages pins
were resolved from the official [configure-pages v5](https://github.com/actions/configure-pages/releases/tag/v5),
[upload-pages-artifact v3](https://github.com/actions/upload-pages-artifact/releases/tag/v3),
and [deploy-pages v5](https://github.com/actions/deploy-pages/releases/tag/v5) releases.
Dependabot proposes weekly Actions/Python updates; review them, never auto-merge.

This gate does not await the separate CodeQL workflow, execute SQL/browser tests,
or deploy Supabase functions/migrations. Runner Node and transitive action
dependencies are not fully pinned. Validate the first GitHub run before release.

For local Windows validation where `python` resolves to an unavailable Windows
Store alias, this session uses the bundled runtime below (Python 3.12.14, 64-bit
AMD64, with `openpyxl` 3.1.5). The PATH change applies only to the current shell
and child npm processes; it does not alter parent files or machine settings.

```powershell
$env:PATH = 'C:\Users\deivi\.cache\codex-runtimes\codex-primary-runtime\dependencies\python;' + $env:PATH
$env:PYTHONDONTWRITEBYTECODE = '1'
python -c "import sys; print(sys.executable); print(sys.version)"
npm test
node tests/single-session-frontend.test.cjs
```

The parent has now included `test:session` in canonical `npm test`; the homolog
mirror package includes it too. The Pages regression job also explicitly covers
the session suite. Running it separately remains useful for focused validation.

## Protect main and executor main

1. With authorized repository owners, inspect current rulesets, collaborators,
   bypass actors, Pages source, environment rules, and actual check names.
2. Protect `main` in `crm-autopecas-supabase` and the active Pages mirror
   `crm-autopecas-supabase-homolog`: require PR review, resolved conversations,
   current successful checks, and block force-push, deletion, and direct pushes.
   Require the actual `Security regression` and both CodeQL language checks from
   `Security checks`; do not use a workflow title as a guessed check name.
3. `static.yml` has no PR trigger, so do not require `Deploy regression` on PRs:
   it cannot report there. Its same-run dependency protects deployment after
   merge/manual dispatch. Keep the existing PR regression in `security.yml`.
4. Restrict `github-pages` deployment branches to `main` and require an approved
   production reviewer where supported. Inspect alternate Pages workflows and
   the mirror so they cannot publish an untested revision outside this gate.
5. Protect `main` in `ips-crm-excel-sync-private` with PR review and its existing
   applicable checks. Confirm names on a real PR before requiring them. Preserve
   executor inputs/schedules and least-privilege secrets; do not enable data sync
   as part of this change. Keep `DATA_SYNC_ENABLED=false` until authorized E2E
   validation, and verify GitHub owners/admins have their own 2FA enabled.

## Auth hardening and personal MFA

1. Inspect Supabase Auth settings per environment and enable leaked password
   protection if supported by the current plan. Record any unavailable control
   as an unresolved blocker, not an enabled setting. Test rejection using a
   disposable homologacao account, without logging or sharing passwords.
2. Confirm existing password rules, login rate limits, session duration and
   single-active-session enforcement against the parent session's final code.
   Test two independent clients: replacement invalidates the previous session,
   logout/revocation works, and normal CRM/B2B access remains intact. Local static
   tests alone do not prove live session invalidation or RLS.
3. Each ADMIN must personally enroll and verify MFA in their own authenticated
   account using their own device. The user must enroll themselves; an agent
   must not handle QR codes, TOTP seeds/codes, or recovery credentials. Supabase
   organization/dashboard MFA and CRM application ADMIN MFA are distinct; verify
   both where applicable. Enrollment alone does not enforce application AAL2.
4. Verify existing server-side ADMIN MFA enforcement and recovery access with an
   authorized owner before making it mandatory. Do not lock out the only admin.
   If the current application cannot enroll/enforce MFA, report the gap for a
   separately authorized task; do not claim this documentation implements it.

## Backup before mutation

1. Locate the existing `pgdump` job with the operator. Verify target project,
   schedule/timezone, runner, credentials, protected storage, notifications,
   retention, and last successful run; distinguish database backup from the
   OneDrive workbook version backup. Do not create a replacement backup system.
2. After authorization, configure the existing job for daily execution and a
   minimum 30-day retention. Check the actual storage lifecycle as well as job
   settings, verify successful daily dumps and timestamps, and alert on failure
   or a missing expected daily backup. Confirm 30 days of recoverable coverage
   (or record coverage still accumulating), not just a retention setting.
3. Generate a fresh prechange dump for the selected environment. Record project,
   timestamp, size, checksum, exit status, owner and private storage location.
   Verify archive readability and restore schema/data/roles/ACLs into an isolated
   disposable database using compatible PostgreSQL tools. Document exclusions,
   separately protected secrets/Storage objects, and available PITR coverage.
4. Keep the prechange recovery point until rollout sign-off. Failed, stale,
   unreadable, or untested backups block migrations and function deployments.
   Do not delete old recovery points just to obtain a clean retention report.

## Recover baseline without reset

Local files include `001_schema.sql` and `001_part1.sql` through `001_part3.sql`;
the sequence checker now expects 001-103 and allows historical 001 parts. Older docs
describe missing baseline 001-042. Neither filenames nor historical notes prove
that local and remote histories agree. The checker validates filename continuity,
not SQL behavior or remote application status. Require explicit review and SQL
regression evidence for 100-103 even when `npm run check` passes.

1. After verified backup, compare the exact approved Git revision, trusted
   historical exports/backups, read-only remote schema/ACL exports, and remote
   migration history (`npm run supabase:migrations:status`, with verified target).
2. Recover missing originals from trusted history, preserving versions and
   contents. Reconcile definitions, owners, grants, triggers and RLS, not merely
   migration numbers. Do not fabricate old migrations from assumptions, renumber,
   rewrite applied files, or run recovered baseline SQL against an existing DB.
3. Rebuild in an isolated disposable environment and compare with the backed-up
   baseline. Review pending migrations/dry-run output only after reconciliation.
   If history repair is necessary, require evidence of each already-applied
   version and explicit owner approval; never blindly mark versions applied.
4. Stop on divergence. No `supabase db reset`, database drop, destructive restore,
   blanket migration-history repair, or unattended `db push` against a live DB.
   Use reviewed forward corrections when needed; this session edits no migrations.

## Function deployment order

1. Confirm backup/restore evidence, baseline reconciliation, explicit target and
   authorization, successful CI/local `npm test`, and reviewed SQL/security
   regressions in a disposable DB or controlled transaction with `ROLLBACK`.
2. Compare remote function inventory/versions/configuration with the same approved
   source revision. Treat missing `b2b-admin` / `b2b-change-password` and outdated
   public `consulta-cnpj` / `cadastro-cliente` as items to verify, not remotely
   observed facts. Record previous artifacts/configuration for rollback.
3. Only after backup and tests, stage the reviewed backend foundation 100 and
   cutover guards 101/102 as described below, then deploy `crm-login`, session-aware
   B2B functions and only public functions confirmed outdated. Do not redeploy every function or
   change `excel-sync`. Verify existing secrets, allowed origins, JWT/auth
   requirements, and public endpoint configuration explicitly; never globally
   disable JWT verification to fix an authorization failure.
4. Verify B2B functions deny missing/invalid sessions; `b2b-admin` denies non-ADMIN
   users; password changes do not expose passwords or bypass account activation.
   Verify public functions preserve their intended unauthenticated contract,
   CORS, allowlisted input, rate limits and sanitized responses. Use authorized
   disposable accounts/data for mutating tests in homologacao.
5. Confirm `SECURITY DEFINER` owners, fixed safe `search_path`, RLS/identity checks,
   and signature-specific role grants. No blanket anon EXECUTE on SECURITY DEFINER
   functions, no `GRANT EXECUTE ON ALL FUNCTIONS ... TO anon`, and no broad PUBLIC
   grant to bypass failures. Public pre-login RPC exceptions require explicit
   review and scoped grants; CRM/B2B internal functions must deny anonymous use.
6. Publish compatible frontend only after backend smoke tests and the gated Pages
   regression pass, then activate 103 only after the validation below. Promote
   that exact homologacao-approved revision to production with the same staged
   order, a fresh verified backup and explicit approval. Record commit, project,
   function versions, test evidence, approver and timestamps without secrets.

## Staged foundation and activation

1. Review `100_security_and_single_session_foundation.sql` against the reconciled
   baseline and test it before authorized application. It creates session state
   and RPCs with `app_session_policy.enforced=false`; it does not yet enforce one
   active application session. It still changes restrictive RLS, request checks,
   grants and policies, so false is not a no-op or a substitute for regression
   tests. An existing PostgREST pre-request integration must be reviewed; do not
   override it to bypass the migration's safety check. Foundation 100 is already
   applied in homologacao according to the parent; preserve it unchanged and do
   not replay it there. Any correction must be a reviewed forward migration.
2. Review and test `101_single_session_cutover_guards.sql`, then apply only with
   backup and authorization. It grants EXECUTE on the single pre-request hook
   `public.check_app_session_request()` to `anon` and `service_role`, because the
   hook runs as the request role. The hook returns no private data and bypasses
   session checks for non-authenticated request roles; endpoint/RPC/table grants
   still apply. This scoped hook grant is not blanket anon EXECUTE on SECURITY
   DEFINER functions and does not expose the username resolver. Verify intended
   public requests work while protected requests remain denied.
   It also serializes `release_app_session()` using the same per-user transaction
   advisory lock as claim, retaining the matching-session condition and denying
   anonymous release. Test concurrent claim/release and replay so an older logout
   cannot clear the winning session. Migration 101 does not enable enforcement;
   verify `enforced=false` throughout this staged review. The parent reports 101
   already applied in homologacao; preserve it unchanged and do not replay it.
3. Review and test `102_monotonic_app_session_claim.sql` before authorized
   application. It preserves per-user advisory serialization and makes the claim
   conflict upsert atomic: update only for the same active session ID or a strictly
   newer Auth creation timestamp. It checks the affected row count and raises
   `PT401` / `SESSAO_SUBSTITUIDA` if the write loses. Test concurrent activation
   seeding, claim/replay and release to verify the newer watermark cannot be
   overwritten by an older claimant. Migration 102 does not activate enforcement;
   keep this review staged with `enforced=false`.
4. Deploy and validate `crm-login` after foundation 100 and guards 101/102, before
   activation 103.
   CRM username/password login now resolves identity server-side using
   `service_role`, rather than exposing the anonymous username-to-email resolver.
   Inputs containing `@` are lowercased and passed directly to Supabase Auth for
   email-login parity; only usernames use server-side identity resolution. Verify
   both paths with active, inactive and invalid disposable accounts.
   The endpoint uses salted hashed-IP rate limiting (currently 30 attempts per
   900 seconds), generic credential errors, and no credential/token logging.
   Validate trusted proxy IP handling and effective rate limits in homologacao.
   This is intentionally a pre-login endpoint: verify its specific gateway
   configuration allows requests without a user JWT while retaining credential
   validation, allowed origins and rate limiting. Do not relax other endpoints.
5. Deploy compatible session-aware `b2b-admin` / `b2b-change-password`, then the
   CRM/B2B frontend and session guard through the Pages gate. Verify usernames,
   email login, password recovery, explicit session claims, restore without
   reclaim, replacement handling and scoped local logout with disposable accounts.
   Confirm every active deployment/mirror is compatible before cutting access to
   the old resolver. Do not combine staged 100-102 and activation 103 in an
   unattended migration push.
6. Only after these stages and explicit authorization, apply
   `103_activate_single_session.sql`. It seeds latest eligible existing Auth
   sessions where no application session row exists and advances an existing row
   only when the incoming Auth `created_at` is strictly higher than its recorded
   `auth_created_at`. Equal/older timestamps cannot lower or overwrite the
   watermark, including released-session state. Test this cutover upsert before
   activation. Migration 103 sets `enforced=true` and
   revokes EXECUTE on `public.resolve_login_email(text)` from `PUBLIC`, `anon`, and
   `authenticated`, retaining `service_role` for `crm-login`. The frontend must
   no longer call `resolveLoginEmail` / the anonymous resolver directly.
7. Verify the policy flag and signature-specific grants read-only, then test two
   independent clients for CRM and B2B. Check older sessions cannot reclaim access
   or mutate data, the current session works, and logout/password-change flows
   remain correct. Record live RLS/RPC/Edge Function evidence separately from
   mocked frontend tests. If checks fail, stop promotion and follow the pause
   procedure; do not re-grant the resolver to anonymous/authenticated clients.

## Stop and rollback

Stop on failed tests, unexplained history drift, backup gaps, missing admin
recovery, authorization bypass, or unverified deployment target. Disable the
existing executor if an authorized integration rollback is needed. Restore known
function/frontend artifacts without reverting unrelated changes, but never restore
a frontend that depends on resolver grants revoked by 103. The reviewed emergency
pause is `supabase/rollback/103_single_session_pause.sql`, applied only with explicit
authorization: it sets `enforced=false` and reloads PostgREST configuration without
deleting session/audit state or undoing secure username login, restricted resolver
grants, or corrected RLS. It pauses the single-session restriction, not all backend
hardening; valid Auth sessions can again pass the paused session gate. Re-enabling
requires renewed compatible-client and session-state checks, not blind replay of
an already-recorded migration. Prefer reviewed
forward database corrections; live data restore/PITR requires a separate owner
decision because post-backup writes may be lost. This document/config change does
not perform any remote operation, commit, function publication, or migration.
