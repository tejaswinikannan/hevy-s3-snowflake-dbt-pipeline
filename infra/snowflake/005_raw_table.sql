-- Run as ACCOUNTADMIN in Snowsight.
-- Raw landing table, matching workouts.csv's actual columns exactly.
--
-- Deliberately typed as STRING for everything (even the numeric-looking
-- columns like weight_lbs, set_index). This is standard for a RAW layer:
-- keep raw data exactly as the source sent it, with no casting that could
-- fail or silently coerce weird values during COPY INTO. Real typing
-- (timestamps, numbers) happens in the bronze layer (Phase 5), where a
-- casting failure is a dbt error you can see and fix, not a load that
-- silently rejects rows.

USE DATABASE hevy;
USE SCHEMA raw;

CREATE TABLE IF NOT EXISTS hevy_export (
  title             STRING,
  start_time        STRING,
  end_time          STRING,
  description       STRING,
  exercise_title    STRING,
  superset_id       STRING,
  exercise_notes    STRING,
  set_index         STRING,
  set_type          STRING,
  weight_lbs        STRING,
  reps              STRING,
  distance_miles    STRING,
  duration_seconds  STRING,
  rpe               STRING,
  _loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()  -- when COPY INTO landed this row, for auditing
);

-- Sanity check
DESCRIBE TABLE hevy_export;
