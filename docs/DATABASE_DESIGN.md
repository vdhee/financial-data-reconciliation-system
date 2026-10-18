# Database design

## Existing core entities
- `RECON_BATCHES`: processing unit and batch lifecycle.
- `SOURCE_TRANSACTIONS`, `TARGET_TRANSACTIONS`: transaction rows from each system.
- `RECON_RECORDS`: one reconciliation outcome per transaction reference and batch.
- `RECON_EXCEPTIONS`: actionable discrepancies linked to a reconciliation record.

## Added operational entities
- `SOURCE_SYSTEMS`: system metadata.
- `CURRENCY_REFERENCE`: supported currency codes.
- `RECON_RULES`: active comparison tolerance / rule configuration.
- `RECON_RUN_HISTORY`: every processing attempt and its outcome.
- `BATCH_CONTROL_TOTALS`: row count and amount totals for each side.
- `DATA_QUALITY_ISSUES`: malformed or incomplete source data.
- `TRANSACTION_DUPLICATES`: duplicate-reference findings.
- `EXCEPTION_ASSIGNMENTS`: current/previous exception ownership.
- `EXCEPTION_HISTORY`: exception state transition log.
- `RECON_AUDIT_LOG`: key lifecycle events.

## Relationships
- One batch has many source and target transactions.
- One batch has multiple run-history entries over its lifetime.
- One batch has control totals for each side.
- One reconciliation record can have one active exception record in the original model.
- One exception can have multiple history and assignment events.
- Data-quality and duplicate findings are batch-scoped.

## Matching policy
Demo match key: `(BATCH_ID, TRANSACTION_REF)`.
- If a reference appears only in source: `MISSING_IN_TARGET`.
- If a reference appears only in target: `MISSING_IN_SOURCE`.
- If a reference occurs more than once on either side: record a duplicate finding and do not arbitrarily pair the duplicate group.
- If both sides contain a unique reference, compare presence of amount, amount tolerance, currency, then amount.
- Transaction date is retained for analysis but not used as a key in this version.

## Transaction ownership
Business procedure does not commit or roll back. The caller controls transaction boundaries. Autonomous audit logging is limited to operational event logging and does not contain transaction payloads or secrets.

## Production considerations not fully implemented
Authentication/authorization, secret management, scheduler orchestration, partitioning, immutable raw-file storage, maker-checker approvals, full multi-currency FX conversion, and regulated audit controls would require additional engineering.
