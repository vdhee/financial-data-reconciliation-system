CREATE OR REPLACE PROCEDURE PRC_RECONCILE_BATCH_V2 (
    P_BATCH_ID IN NUMBER
)
AS
    V_BATCH_STATUS       RECON_BATCHES.BATCH_STATUS%TYPE;
    V_RUN_NUMBER         NUMBER;
    V_RUN_ID             RECON_RUN_HISTORY.RUN_ID%TYPE;
    V_SOURCE_COUNT       NUMBER := 0;
    V_TARGET_COUNT       NUMBER := 0;
    V_RECON_COUNT        NUMBER := 0;
    V_PROCESSING_STARTED BOOLEAN := FALSE;
    V_RUN_CREATED        BOOLEAN := FALSE;
    V_ERROR_CODE         NUMBER;
    V_ERROR_MESSAGE      VARCHAR2(2000);
BEGIN
    ------------------------------------------------------------------
    -- 1. Validate the batch without changing its status.
    ------------------------------------------------------------------
    BEGIN
        SELECT BATCH_STATUS
          INTO V_BATCH_STATUS
          FROM RECON_BATCHES
         WHERE BATCH_ID = P_BATCH_ID;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20100, 'Batch ID does not exist.');
    END;

    IF V_BATCH_STATUS <> 'PENDING' THEN
        RAISE_APPLICATION_ERROR(
            -20101,
            'Only PENDING batches can be reconciled. Current status: ' || V_BATCH_STATUS
        );
    END IF;

    ------------------------------------------------------------------
    -- 2. Atomically claim the batch. The row lock remains until the
    --    caller commits or rolls back the transaction.
    ------------------------------------------------------------------
    UPDATE RECON_BATCHES
       SET BATCH_STATUS = 'PROCESSING'
     WHERE BATCH_ID = P_BATCH_ID
       AND BATCH_STATUS = 'PENDING';

    IF SQL%ROWCOUNT <> 1 THEN
        RAISE_APPLICATION_ERROR(-20102, 'Batch is no longer PENDING.');
    END IF;

    V_PROCESSING_STARTED := TRUE;

    ------------------------------------------------------------------
    -- 3. Create a run-history row. The batch row has been claimed,
    --    so concurrent attempts for this batch must wait.
    ------------------------------------------------------------------
    SELECT NVL(MAX(RUN_NUMBER), 0) + 1
      INTO V_RUN_NUMBER
      FROM RECON_RUN_HISTORY
     WHERE BATCH_ID = P_BATCH_ID;

    INSERT INTO RECON_RUN_HISTORY (
        BATCH_ID, RUN_NUMBER, RUN_STATUS, STARTED_AT
    ) VALUES (
        P_BATCH_ID, V_RUN_NUMBER, 'STARTED', SYSTIMESTAMP
    )
    RETURNING RUN_ID INTO V_RUN_ID;

    V_RUN_CREATED := TRUE;

    -- Preserve the claimed batch and run row if later reconciliation
    -- work fails. This procedure does not COMMIT or ROLLBACK the caller's
    -- whole transaction; the caller owns the final transaction decision.
    SAVEPOINT RECON_WORK_START;

    PKG_RECON_SUPPORT.PRC_LOG_EVENT(
        P_BATCH_ID, V_RUN_ID, 'RECON_START', 'INFO', 'Reconciliation started.'
    );

    ------------------------------------------------------------------
    -- 4. Detect duplicate references on the source side.
    ------------------------------------------------------------------
    INSERT INTO TRANSACTION_DUPLICATES (
        BATCH_ID, SYSTEM_SIDE, TRANSACTION_REF, DUPLICATE_COUNT
    )
    SELECT P_BATCH_ID, 'SOURCE', d.TRANSACTION_REF, d.DUPLICATE_COUNT
      FROM (
            SELECT TRANSACTION_REF, COUNT(*) AS DUPLICATE_COUNT
              FROM SOURCE_TRANSACTIONS
             WHERE BATCH_ID = P_BATCH_ID
               AND TRANSACTION_REF IS NOT NULL
             GROUP BY TRANSACTION_REF
            HAVING COUNT(*) > 1
           ) d
     WHERE NOT EXISTS (
           SELECT 1
             FROM TRANSACTION_DUPLICATES x
            WHERE x.BATCH_ID = P_BATCH_ID
              AND x.SYSTEM_SIDE = 'SOURCE'
              AND x.TRANSACTION_REF = d.TRANSACTION_REF
     );

    ------------------------------------------------------------------
    -- 5. Detect duplicate references on the target side.
    ------------------------------------------------------------------
    INSERT INTO TRANSACTION_DUPLICATES (
        BATCH_ID, SYSTEM_SIDE, TRANSACTION_REF, DUPLICATE_COUNT
    )
    SELECT P_BATCH_ID, 'TARGET', d.TRANSACTION_REF, d.DUPLICATE_COUNT
      FROM (
            SELECT TRANSACTION_REF, COUNT(*) AS DUPLICATE_COUNT
              FROM TARGET_TRANSACTIONS
             WHERE BATCH_ID = P_BATCH_ID
               AND TRANSACTION_REF IS NOT NULL
             GROUP BY TRANSACTION_REF
            HAVING COUNT(*) > 1
           ) d
     WHERE NOT EXISTS (
           SELECT 1
             FROM TRANSACTION_DUPLICATES x
            WHERE x.BATCH_ID = P_BATCH_ID
              AND x.SYSTEM_SIDE = 'TARGET'
              AND x.TRANSACTION_REF = d.TRANSACTION_REF
     );

    ------------------------------------------------------------------
    -- 6. Record source data-quality issues. NULL-aware matching avoids
    --    repeatedly inserting an issue for a NULL transaction reference.
    --    Note: without a source-row ID, identical bad rows with NULL refs
    --    cannot be individually distinguished in DATA_QUALITY_ISSUES.
    ------------------------------------------------------------------
    INSERT INTO DATA_QUALITY_ISSUES (
        BATCH_ID, SYSTEM_SIDE, TRANSACTION_REF, ISSUE_TYPE, ISSUE_DETAILS
    )
    SELECT P_BATCH_ID,
           'SOURCE',
           s.TRANSACTION_REF,
           CASE WHEN s.TRANSACTION_REF IS NULL
                THEN 'NULL_REFERENCE' ELSE 'NULL_AMOUNT' END,
           CASE WHEN s.TRANSACTION_REF IS NULL
                THEN 'Source transaction reference is null.'
                ELSE 'Source transaction amount is null.' END
      FROM SOURCE_TRANSACTIONS s
     WHERE s.BATCH_ID = P_BATCH_ID
       AND (s.TRANSACTION_REF IS NULL OR s.AMOUNT IS NULL)
       AND NOT EXISTS (
           SELECT 1
             FROM DATA_QUALITY_ISSUES q
            WHERE q.BATCH_ID = P_BATCH_ID
              AND q.SYSTEM_SIDE = 'SOURCE'
              AND q.ISSUE_TYPE = CASE WHEN s.TRANSACTION_REF IS NULL
                                      THEN 'NULL_REFERENCE' ELSE 'NULL_AMOUNT' END
              AND (q.TRANSACTION_REF = s.TRANSACTION_REF
                   OR (q.TRANSACTION_REF IS NULL AND s.TRANSACTION_REF IS NULL))
       );

    ------------------------------------------------------------------
    -- 7. Record target data-quality issues.
    ------------------------------------------------------------------
    INSERT INTO DATA_QUALITY_ISSUES (
        BATCH_ID, SYSTEM_SIDE, TRANSACTION_REF, ISSUE_TYPE, ISSUE_DETAILS
    )
    SELECT P_BATCH_ID,
           'TARGET',
           t.TRANSACTION_REF,
           CASE WHEN t.TRANSACTION_REF IS NULL
                THEN 'NULL_REFERENCE' ELSE 'NULL_AMOUNT' END,
           CASE WHEN t.TRANSACTION_REF IS NULL
                THEN 'Target transaction reference is null.'
                ELSE 'Target transaction amount is null.' END
      FROM TARGET_TRANSACTIONS t
     WHERE t.BATCH_ID = P_BATCH_ID
       AND (t.TRANSACTION_REF IS NULL OR t.AMOUNT IS NULL)
       AND NOT EXISTS (
           SELECT 1
             FROM DATA_QUALITY_ISSUES q
            WHERE q.BATCH_ID = P_BATCH_ID
              AND q.SYSTEM_SIDE = 'TARGET'
              AND q.ISSUE_TYPE = CASE WHEN t.TRANSACTION_REF IS NULL
                                      THEN 'NULL_REFERENCE' ELSE 'NULL_AMOUNT' END
              AND (q.TRANSACTION_REF = t.TRANSACTION_REF
                   OR (q.TRANSACTION_REF IS NULL AND t.TRANSACTION_REF IS NULL))
       );

    ------------------------------------------------------------------
    -- 8. Reconcile only non-NULL references that are unique on each
    --    side. Duplicate references and NULL references are reported
    --    separately and are not joined into reconciliation results.
    ------------------------------------------------------------------
    INSERT INTO RECON_RECORDS (
        BATCH_ID, TRANSACTION_REF, SOURCE_AMOUNT, TARGET_AMOUNT, RECON_STATUS
    )
    WITH S AS (
        SELECT s.BATCH_ID, s.TRANSACTION_REF, s.AMOUNT, s.CURRENCY_CODE
          FROM SOURCE_TRANSACTIONS s
         WHERE s.BATCH_ID = P_BATCH_ID
           AND s.TRANSACTION_REF IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
                 FROM SOURCE_TRANSACTIONS sx
                WHERE sx.BATCH_ID = s.BATCH_ID
                  AND sx.TRANSACTION_REF = s.TRANSACTION_REF
                GROUP BY sx.BATCH_ID, sx.TRANSACTION_REF
               HAVING COUNT(*) > 1
           )
    ),
    T AS (
        SELECT t.BATCH_ID, t.TRANSACTION_REF, t.AMOUNT, t.CURRENCY_CODE
          FROM TARGET_TRANSACTIONS t
         WHERE t.BATCH_ID = P_BATCH_ID
           AND t.TRANSACTION_REF IS NOT NULL
           AND NOT EXISTS (
               SELECT 1
                 FROM TARGET_TRANSACTIONS tx
                WHERE tx.BATCH_ID = t.BATCH_ID
                  AND tx.TRANSACTION_REF = t.TRANSACTION_REF
                GROUP BY tx.BATCH_ID, tx.TRANSACTION_REF
               HAVING COUNT(*) > 1
           )
    )
    SELECT P_BATCH_ID,
           COALESCE(s.TRANSACTION_REF, t.TRANSACTION_REF),
           s.AMOUNT,
           t.AMOUNT,
           CASE
               WHEN s.TRANSACTION_REF IS NULL THEN 'MISSING_IN_SOURCE'
               WHEN t.TRANSACTION_REF IS NULL THEN 'MISSING_IN_TARGET'
               WHEN s.AMOUNT IS NULL OR t.AMOUNT IS NULL THEN 'MISSING_DATA'
               WHEN NVL(s.CURRENCY_CODE, '?') <> NVL(t.CURRENCY_CODE, '?')
                    THEN 'CURRENCY_MISMATCH'
               WHEN s.AMOUNT = t.AMOUNT THEN 'MATCHED'
               ELSE 'MISMATCH'
           END
      FROM S s
      FULL OUTER JOIN T t
        ON t.BATCH_ID = s.BATCH_ID
       AND t.TRANSACTION_REF = s.TRANSACTION_REF
     WHERE COALESCE(s.BATCH_ID, t.BATCH_ID) = P_BATCH_ID
       AND NOT EXISTS (
           SELECT 1
             FROM RECON_RECORDS r
            WHERE r.BATCH_ID = P_BATCH_ID
              AND r.TRANSACTION_REF = COALESCE(s.TRANSACTION_REF, t.TRANSACTION_REF)
       );

    ------------------------------------------------------------------
    -- 9. Create exceptions for discrepancies. The package is expected
    --    to insert only missing exception rows and not COMMIT.
    ------------------------------------------------------------------
    PKG_RECON_SUPPORT.PRC_LOAD_EXCEPTIONS(P_BATCH_ID);

    ------------------------------------------------------------------
    -- 10. Capture control totals. This design assumes one currency per
    --     batch/system side. Mixed-currency batches require totals by
    --     currency and a corresponding unique key on the control table.
    ------------------------------------------------------------------
    MERGE INTO BATCH_CONTROL_TOTALS d
    USING (
        SELECT P_BATCH_ID AS BATCH_ID,
               'SOURCE' AS SYSTEM_SIDE,
               COUNT(*) AS TRANSACTION_COUNT,
               SUM(AMOUNT) AS TOTAL_AMOUNT,
               MIN(CURRENCY_CODE) AS CURRENCY_CODE
          FROM SOURCE_TRANSACTIONS
         WHERE BATCH_ID = P_BATCH_ID
        UNION ALL
        SELECT P_BATCH_ID,
               'TARGET',
               COUNT(*),
               SUM(AMOUNT),
               MIN(CURRENCY_CODE)
          FROM TARGET_TRANSACTIONS
         WHERE BATCH_ID = P_BATCH_ID
    ) s
       ON (d.BATCH_ID = s.BATCH_ID AND d.SYSTEM_SIDE = s.SYSTEM_SIDE)
    WHEN MATCHED THEN UPDATE SET
        d.TRANSACTION_COUNT = s.TRANSACTION_COUNT,
        d.TOTAL_AMOUNT = s.TOTAL_AMOUNT,
        d.CURRENCY_CODE = s.CURRENCY_CODE,
        d.CAPTURED_AT = SYSTIMESTAMP
    WHEN NOT MATCHED THEN INSERT (
        BATCH_ID, SYSTEM_SIDE, TRANSACTION_COUNT, TOTAL_AMOUNT,
        CURRENCY_CODE, CAPTURED_AT
    ) VALUES (
        s.BATCH_ID, s.SYSTEM_SIDE, s.TRANSACTION_COUNT, s.TOTAL_AMOUNT,
        s.CURRENCY_CODE, SYSTIMESTAMP
    );

    ------------------------------------------------------------------
    -- 11. Record final row counts and mark the batch/run completed.
    ------------------------------------------------------------------
    SELECT COUNT(*)
      INTO V_SOURCE_COUNT
      FROM SOURCE_TRANSACTIONS
     WHERE BATCH_ID = P_BATCH_ID;

    SELECT COUNT(*)
      INTO V_TARGET_COUNT
      FROM TARGET_TRANSACTIONS
     WHERE BATCH_ID = P_BATCH_ID;

    SELECT COUNT(*)
      INTO V_RECON_COUNT
      FROM RECON_RECORDS
     WHERE BATCH_ID = P_BATCH_ID;

    UPDATE RECON_RUN_HISTORY
       SET RUN_STATUS = 'COMPLETED',
           ENDED_AT = SYSTIMESTAMP,
           SOURCE_ROW_COUNT = V_SOURCE_COUNT,
           TARGET_ROW_COUNT = V_TARGET_COUNT,
           RECON_ROW_COUNT = V_RECON_COUNT,
           ERROR_CODE = NULL,
           ERROR_MESSAGE = NULL
     WHERE RUN_ID = V_RUN_ID;

    UPDATE RECON_BATCHES
       SET BATCH_STATUS = 'COMPLETED'
     WHERE BATCH_ID = P_BATCH_ID
       AND BATCH_STATUS = 'PROCESSING';

    IF SQL%ROWCOUNT <> 1 THEN
        RAISE_APPLICATION_ERROR(-20103, 'Batch status changed unexpectedly during reconciliation.');
    END IF;

    PKG_RECON_SUPPORT.PRC_LOG_EVENT(
        P_BATCH_ID,
        V_RUN_ID,
        'RECON_COMPLETE',
        'SUCCESS',
        'Reconciliation completed. Source rows=' || V_SOURCE_COUNT ||
        ', target rows=' || V_TARGET_COUNT ||
        ', reconciliation rows=' || V_RECON_COUNT
    );

    -- Intentionally no COMMIT: the caller owns the transaction.

EXCEPTION
    WHEN OTHERS THEN
        V_ERROR_CODE := SQLCODE;
        V_ERROR_MESSAGE := SUBSTR(SQLERRM, 1, 2000);

        IF V_PROCESSING_STARTED THEN
            -- Undo reconciliation changes while preserving the batch claim
            -- and run-history row created before the savepoint.
            BEGIN
                ROLLBACK TO RECON_WORK_START;
            EXCEPTION
                WHEN OTHERS THEN
                    -- The savepoint may not exist if run creation failed.
                    -- Do not replace the original error with this one.
                    NULL;
            END;

            IF V_RUN_CREATED AND V_RUN_ID IS NOT NULL THEN
                UPDATE RECON_RUN_HISTORY
                   SET RUN_STATUS = 'FAILED',
                       ENDED_AT = SYSTIMESTAMP,
                       ERROR_CODE = V_ERROR_CODE,
                       ERROR_MESSAGE = V_ERROR_MESSAGE
                 WHERE RUN_ID = V_RUN_ID;
            END IF;

            UPDATE RECON_BATCHES
               SET BATCH_STATUS = 'FAILED'
             WHERE BATCH_ID = P_BATCH_ID
               AND BATCH_STATUS = 'PROCESSING';

            PKG_RECON_SUPPORT.PRC_LOG_EVENT(
                P_BATCH_ID,
                V_RUN_ID,
                'RECON_FAILURE',
                'ERROR',
                V_ERROR_MESSAGE
            );
        END IF;

        -- The caller should COMMIT to persist the FAILED status/run record,
        -- or ROLLBACK to undo the whole transaction. Do not silently commit
        -- unrelated work belonging to the caller.
        RAISE;
END PRC_RECONCILE_BATCH_V2;
/