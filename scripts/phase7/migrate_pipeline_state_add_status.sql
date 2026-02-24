-- Pipeline State status contract alignment migration
-- Run target: Databricks SQL / UC
-- Usage: replace <catalog> with the target catalog name.

ALTER TABLE <catalog>.gold.pipeline_state ADD COLUMNS (status STRING);

UPDATE <catalog>.gold.pipeline_state
SET status = CASE
  WHEN last_success_ts IS NOT NULL AND updated_at = last_success_ts THEN 'success'
  ELSE 'failure'
END
WHERE status IS NULL;

SELECT status, COUNT(*) AS cnt
FROM <catalog>.gold.pipeline_state
GROUP BY status;

SELECT COUNT(*) AS null_status_cnt
FROM <catalog>.gold.pipeline_state
WHERE status IS NULL;

SELECT COUNT(*) AS invalid_status_cnt
FROM <catalog>.gold.pipeline_state
WHERE status NOT IN ('success', 'failure');
