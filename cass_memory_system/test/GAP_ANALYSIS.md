# Unit Test Gap Analysis (No Mocks)

Scope: identify missing or weak unit coverage across src/** using real implementations (no mocks except external APIs/console).

## Current coverage snapshot (manual walk-through)
- High/covered: `llm-with-retry`, portions of `validate`, small utils around diary/formatting.
- Minimal/none: `playbook.ts`, `scoring.ts`, `config.ts`, `curate.ts`, `cass.ts` wrappers, `security.ts`, `tracking.ts`, `lock.ts`, `diary.ts`, `reflect.ts`.
- CLI commands: most commands under `src/commands/*` lack unit-level tests (context/mark/playbook/stats/doctor/reflect/validate).

## Priority order (P0 first)
1) **scoring.ts** — decay, effectiveScore, maturity transitions, stale detection.
2) **playbook.ts** — add/deprecate/pin/unpin/findSimilar/exportToMarkdown, toxic filtering, load/save error paths.
3) **config.ts** — loadConfig merging (global + repo + CLI), expandPath, validation failures.
4) **curate.ts** — delta application (add/helpful/harmful/deprecate/merge), duplication guards, toxic checks.
5) **security.ts** — sanitize patterns and extraPatterns; regression tests on redaction.
6) **tracking.ts / lock.ts** — processed log + file locking semantics (temp dirs).
7) **cass.ts** wrappers — safeCassSearch fallback paths (mock cass binary via temp script).
8) **diary.ts / reflect.ts** — diary parsing, dedup, shouldExitEarly, MAX_DELTAS boundaries.

## Test infrastructure to leverage
- `test/helpers/temp.ts` for temp dirs.
- `test/helpers/factories.ts` for bullets/playbooks/diaries.
- `test/helpers/logger.ts` for structured logging.
- `test/fixtures/*` for baseline playbook/config/diary samples.

## Suggested files to add
- `test/scoring.test.ts` (expand to full P0 cases).
- `test/playbook.test.ts` (CRUD + similarity + markdown export).
- `test/config.test.ts` (merge/validation/expandPath).
- `test/curate.test.ts` (already exists; extend for harmful/merge/deprecate).
- `test/security.test.ts` (redaction patterns).
- `test/tracking.test.ts` (processed log + lock interactions).
- `test/cass.integration.test.ts` (fake cass script to exercise fallbacks).
- `test/diary.test.ts`, `test/reflect.test.ts` (boundary + dedup).
- Command-level smoke unit tests: `test/commands/context.test.ts`, etc., using temp HOME and fixtures.

## Acceptance criteria for closing f63a
- Inventory doc (this file) committed.
- At least one P0 module gets new passing test file with >90% line coverage.
- Clear mapping from modules to planned test files (above) for follow-on beads.

## 2026-01-21 Coverage audit (bd-19eu)
- Heuristic import scan found no direct test imports for `src/audit.ts` (coverage is likely only via `auditCommand` tests).
- Only referenced by E2E tests (no unit/integration/property/fast coverage):
  - `src/commands/guard`
  - `src/commands/init`
  - `src/commands/mark`
  - `src/commands/similar`
  - `src/commands/starters`
  - `src/commands/stats`
  - `src/commands/trauma`
  - `src/commands/usage`
- Suggested follow-ups:
  - ✅ Added direct unit test for `scanSessionsForViolations` in `src/audit.ts` (severity mapping + retired bullet filtering) in `test/audit.test.ts`.
  - Add lightweight unit tests for the command modules above (input validation + JSON error shape).
