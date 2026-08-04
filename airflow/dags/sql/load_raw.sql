-- Loads the full raw CSV export into raw.hevy_export, every run, unfiltered.
--
-- Deliberately NOT filtered by watermark here -- that logic lives entirely
-- in the bronze dbt model (Phase 5), so there's exactly one place that
-- decides "what's new." This keeps the load step trivial and repeatable.
--
-- Snowflake's own load history makes this naturally idempotent: COPY INTO
-- skips files it has already successfully loaded (by default), so
-- re-running this against the same S3 file is a safe no-op.
--
-- Explicit column list (excluding _loaded_at) lets that column fall back to
-- its DEFAULT CURRENT_TIMESTAMP() -- the CSV itself has no such column.

COPY INTO raw.hevy_export (
  title, start_time, end_time, description, exercise_title, superset_id,
  exercise_notes, set_index, set_type, weight_lbs, reps, distance_miles,
  duration_seconds, rpe
)
FROM @hevy_raw_stage
FILE_FORMAT = (FORMAT_NAME = csv_ff)
PATTERN = '.*dt=.*/export[.]csv'
ON_ERROR = 'ABORT_STATEMENT';
