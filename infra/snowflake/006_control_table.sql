-- Run as ACCOUNTADMIN in Snowsight.
-- Watermark control table: tracks how far the pipeline has already loaded,
-- so each weekly run (which re-lands the FULL historical export) can filter
-- down to only genuinely new rows in the bronze dbt model (Phase 5).
--
-- Note: the architecture doc's original design assumed a `completed_at`
-- column; the real Hevy export has no such field. The watermark instead
-- uses `end_time` (a per-workout timestamp shared by every set row in that
-- workout) -- see the corrected schema notes in the build plan.

USE DATABASE hevy;
USE SCHEMA bronze;

CREATE TABLE IF NOT EXISTS pipeline_control (
  pipeline_name        STRING,
  last_watermark_ts    TIMESTAMP_NTZ,
  last_run_ts          TIMESTAMP_NTZ,
  rows_loaded_last_run NUMBER
);

-- Seed exactly one row for this pipeline, starting from the beginning of time
-- so the first-ever bronze run loads everything.
INSERT INTO pipeline_control (pipeline_name, last_watermark_ts, last_run_ts, rows_loaded_last_run)
SELECT 'hevy', '1900-01-01'::TIMESTAMP_NTZ, NULL, 0
WHERE NOT EXISTS (SELECT 1 FROM pipeline_control WHERE pipeline_name = 'hevy');

-- Sanity check
SELECT * FROM pipeline_control;
