# Review of the uploaded version and upgrade notes

## Observed in the uploaded source
- Existing schema has batch, source/target transaction, reconciliation record, and exception tables.
- The original reconciliation procedure assumes transaction references are unique and commits internally.
- `sql/query_runs.sql` mixes exploratory SELECTs, ALTER TABLE statements, and a procedure invocation; it should not be used as a repeatable setup script.
- Existing sample inserts and load scripts are hard-coded to batch ID 1 and selected transaction references.
- Existing exception loading filters on `TXN200%`, so it is not a general batch-level loader.
- The original matching logic compares amount and presence but not currency.
- Existing docs already identified duplicate handling, matching key definition, transaction boundaries, audit history, and concurrency as design risks.

## What this upgrade adds
- Source system, currency, and configurable rule reference data.
- Run history and batch control totals.
- Data-quality findings and duplicate reference inventory.
- Exception assignment and status-history tables.
- Audit events, an upgraded reconciliation procedure, and operational reports.
- Synthetic data generation and smoke/business-rule queries.

## Limitations to state honestly
This is a portfolio project and a learning implementation. It has not been executed against the user's local Oracle database from this environment. Compile and run scripts locally in the documented order. Multi-currency FX conversion, scheduler orchestration, external file ingestion, role-based security, and full production-grade recovery are future enhancements.
