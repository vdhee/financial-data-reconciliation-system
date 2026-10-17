
CREATE OR REPLACE PROCEDURE PRC_RECONCILE_BATCH (
    P_BATCH_ID IN NUMBER
)
AS
BEGIN
    -- Validate the batch before processing
    DECLARE
        V_BATCH_STATUS RECON_BATCHES.BATCH_STATUS%TYPE;
    BEGIN
        SELECT BATCH_STATUS
        INTO V_BATCH_STATUS
        FROM RECON_BATCHES
        WHERE BATCH_ID = P_BATCH_ID
        FOR UPDATE;

        IF V_BATCH_STATUS <> 'PENDING' THEN
            RAISE_APPLICATION_ERROR(
                -20001,
                'Only PENDING batches can be processed.'
            );
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(
                -20002,
                'Batch ID does not exist.'
            );
    END;
    -- Step 1: Compare source and target transactions
    INSERT INTO RECON_RECORDS (
        BATCH_ID,
        TRANSACTION_REF,
        SOURCE_AMOUNT,
        TARGET_AMOUNT,
        RECON_STATUS
    )
    SELECT
        P_BATCH_ID,
        COALESCE(s.TRANSACTION_REF, t.TRANSACTION_REF),
        s.AMOUNT,
        t.AMOUNT,
        CASE
            WHEN s.TRANSACTION_REF IS NULL
                THEN 'MISSING_IN_SOURCE'
            WHEN t.TRANSACTION_REF IS NULL
                THEN 'MISSING_IN_TARGET'
            WHEN s.AMOUNT IS NULL OR t.AMOUNT IS NULL
                THEN 'MISSING_DATA'
            WHEN s.AMOUNT = t.AMOUNT
                THEN 'MATCHED'
            ELSE 'MISMATCH'
        END
    FROM SOURCE_TRANSACTIONS s
    FULL OUTER JOIN TARGET_TRANSACTIONS t
        ON s.BATCH_ID = t.BATCH_ID
       AND s.TRANSACTION_REF = t.TRANSACTION_REF
    WHERE COALESCE(s.BATCH_ID, t.BATCH_ID) = P_BATCH_ID
      AND NOT EXISTS (
          SELECT 1
          FROM RECON_RECORDS r
          WHERE r.BATCH_ID = P_BATCH_ID
            AND r.TRANSACTION_REF =
                COALESCE(s.TRANSACTION_REF, t.TRANSACTION_REF)
      );

    -- Step 2: Create exceptions for unmatched results
    INSERT INTO RECON_EXCEPTIONS (
        RECORD_ID,
        EXCEPTION_TYPE,
        EXCEPTION_AMOUNT
    )
    SELECT
        r.RECORD_ID,
        r.RECON_STATUS,
        CASE
            WHEN r.RECON_STATUS = 'MISMATCH'
                THEN ABS(r.SOURCE_AMOUNT - r.TARGET_AMOUNT)
            ELSE NULL
        END
    FROM RECON_RECORDS r
    WHERE r.BATCH_ID = P_BATCH_ID
      AND r.RECON_STATUS IN (
          'MISMATCH',
          'MISSING_IN_SOURCE',
          'MISSING_IN_TARGET',
          'MISSING_DATA'
      )
      AND NOT EXISTS (
          SELECT 1
          FROM RECON_EXCEPTIONS e
          WHERE e.RECORD_ID = r.RECORD_ID
      );

    -- Step 3: Mark the batch as completed
    UPDATE RECON_BATCHES
    SET BATCH_STATUS = 'COMPLETED'
    WHERE BATCH_ID = P_BATCH_ID;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        UPDATE RECON_BATCHES
        SET BATCH_STATUS = 'FAILED'
        WHERE BATCH_ID = P_BATCH_ID;
        COMMIT;
        RAISE;
END PRC_RECONCILE_BATCH;
/
