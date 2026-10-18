# Database Design

## Relationships
- One batch can have many source transactions, target transactions, and reconciliation records.
- One reconciliation record can have an exception linked by `RECORD_ID`.

## Flow
1. Create a `PENDING` batch.
2. Load source and target transactions.
3. Compare by `BATCH_ID` and `TRANSACTION_REF`.
4. Assign a reconciliation status.
5. Create exceptions for non-matching results.
6. Review reports and resolve exceptions.

## Status values
Batch: `PENDING`, `PROCESSING`, `COMPLETED`, `FAILED`.
Reconciliation: `PENDING`, `MATCHED`, `MISMATCH`, `MISSING_DATA`, `MISSING_IN_SOURCE`, `MISSING_IN_TARGET`.
Exception: `OPEN`, `INVESTIGATING`, `RESOLVED`.

## Design risks to address
- Detect duplicate transaction references before a full outer join; duplicates can multiply rows.
- Define whether currency and transaction date are part of the match key.
- Define transaction boundaries and error logging carefully; a stored procedure should not commit or roll back unrelated caller work.
- Add audit history and test concurrent attempts to process the same batch.
