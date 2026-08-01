-- Run as ACCOUNTADMIN in Snowsight.
-- Dedicated XS warehouse for this pipeline, auto-suspends quickly to keep
-- weekly-run cost near-zero (see architecture doc's cost estimate).

CREATE WAREHOUSE IF NOT EXISTS hevy_wh
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60          -- seconds idle before suspending
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

-- Sanity check
SHOW WAREHOUSES LIKE 'hevy_wh';
