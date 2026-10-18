# Execution guide

## A. Existing project (recommended)
Run one script at a time in VS Code with the `FIN_RECON_LOCAL` connection. Confirm that the connection is `ANALYTICS_PROJECT` in `FREEPDB1`.

1. `migration/01_create_reference_tables.sql`
2. `migration/02_create_operational_tables.sql`
3. `migration/03_create_indexes.sql`
4. `migration/04_extend_exception_types.sql`
5. `packages/01_pkg_recon_support.sql`
6. `packages/02_pkg_exception_workflow.sql`
7. `procedures/01_prc_reconcile_batch_v2.sql`
8. `data/01_seed_reference_data.sql`
9. `data/02_generate_demo_batch.sql`
10. Find the new batch ID from the final query in the generator.
11. Execute `BEGIN PRC_RECONCILE_BATCH_V2(<new_batch_id>); END;`
12. Review the reports in `reports/`.
13. Run `tests/01_schema_smoke_tests.sql` and `tests/02_business_rule_tests.sql`.

## Important transaction notes
- The new procedure intentionally does not `COMMIT` or `ROLLBACK`; the caller owns the transaction.
- After running the procedure successfully, inspect results and then run `COMMIT;` to persist, or `ROLLBACK;` if you are intentionally discarding the test run.
- Audit events are written through a small autonomous transaction so operational log entries can survive caller rollback. This is a portfolio demonstration; production logging requires more careful operational/security design.
- The procedure rejects batches that are not `PENDING`. It detects duplicate references before joining and excludes duplicate groups from arbitrary pairing.
- The demo data generator creates a new batch; it does not use batch ID 1 and does not truncate existing data.
- The generator inserts about 18,000 source and 18,000 target rows plus duplicate examples. Adjust `V_ROWS` only if you also review the corresponding target loops.

## Re-run safety
These migration scripts are additive but are not a migration framework: running them twice can return ORA-00955 because objects already exist. If a script partially fails, inspect `USER_OBJECTS` and `USER_ERRORS` before deciding what to rerun. Do not drop existing project objects blindly.

## Troubleshooting
- ORA-00955: object already exists. Check whether the script was already run; don't blindly drop the object.
- ORA-02291/ORA-02292: foreign-key parent/child ordering or existing dependent rows.
- ORA-01400: required field missing in insert.
- ORA-00001: duplicate unique key; inspect transaction reference uniqueness and rerun controls.
- PL/SQL compile errors: query `USER_ERRORS` for the object name.
