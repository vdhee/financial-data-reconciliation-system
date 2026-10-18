# Financial Data Reconciliation & Exception Management Platform

A portfolio-grade Oracle SQL/PLSQL project that reconciles financial transactions across source and target systems, detects data-quality problems, records exceptions, tracks batch runs, and supports operational reporting.

## Environment
- Oracle Database Free / Oracle AI Database Free (tested target: Oracle 23ai/26ai-compatible SQL features)
- VS Code + Oracle SQL Developer extension
- Schema: use your own development schema (the original project used `ANALYTICS_PROJECT`)

## Important: safe upgrade path
This bundle includes:
- `migration/` — additive upgrade for the existing project schema. This is the path to use first.
- `data/` — synthetic dataset generator for a new demo batch.
- `packages/`, `procedures/`, `reports/`, `tests/` — new modules and checks.
- `docs/` — design, execution guide, glossary, and interview notes.
- `legacy_reference/` — original scripts retained for comparison, not for re-running as a batch.

## Before you run anything
1. Commit or create a Git branch/backup of your current repository.
2. Connect to the intended PDB and confirm `USER` and `CON_NAME`.
3. Review every script. This project uses synthetic data only.
4. Run scripts in the order in `docs/EXECUTION_GUIDE.md`.
5. Never include passwords, wallet files, production extracts, or real customer data in Git.

## Key design decisions
- Transaction matching key for this demo: `(BATCH_ID, TRANSACTION_REF)`.
- Currency and transaction date are comparison attributes, not part of the key. A reference that exists on both sides but has a currency difference is an exception, not two missing transactions.
- Duplicate references are identified before reconciliation. The demo avoids arbitrary one-to-many pairing.
- Amounts use `NUMBER(15,2)` and currency codes use ISO-like three-character codes.
- The reconciliation procedure does not issue `COMMIT` or `ROLLBACK`; transaction ownership belongs to the caller. Failed run information is recorded using a small autonomous logging routine.
- Re-running the same batch is blocked unless the caller explicitly resets/reopens it through a controlled workflow.
- Data volumes are synthetic and adjustable. Begin with 20,000–100,000 rows per source and measure your environment before increasing.

## Current implementation scope
The upgrade adds reference data, run history, control totals, rule configuration, data-quality findings, duplicate findings, exception assignment/history, and audit logging. It provides a v2 reconciliation procedure that works alongside the original procedure until you validate and choose to switch over.

This is a learning/portfolio system, not a certified banking or production settlement platform.
