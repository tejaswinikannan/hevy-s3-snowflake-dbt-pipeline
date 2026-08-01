-- Run as ACCOUNTADMIN in Snowsight.
-- A scoped role for day-to-day pipeline runs (dbt, Airflow), so weekly runs
-- never use ACCOUNTADMIN. Mirrors the least-privilege approach used for the
-- AWS IAM user/role in Phase 1.

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS HEVY_PIPELINE_ROLE;

-- Warehouse: just enough to run queries
GRANT USAGE ON WAREHOUSE hevy_wh TO ROLE HEVY_PIPELINE_ROLE;

-- Database + all three schemas
GRANT USAGE ON DATABASE hevy TO ROLE HEVY_PIPELINE_ROLE;
GRANT USAGE ON SCHEMA hevy.raw TO ROLE HEVY_PIPELINE_ROLE;
GRANT USAGE ON SCHEMA hevy.bronze TO ROLE HEVY_PIPELINE_ROLE;
GRANT USAGE ON SCHEMA hevy.gold TO ROLE HEVY_PIPELINE_ROLE;

-- raw: COPY INTO needs SELECT+INSERT on the table, plus USAGE on the stage,
-- file format, and the underlying storage integration it references.
GRANT SELECT, INSERT ON TABLE hevy.raw.hevy_export TO ROLE HEVY_PIPELINE_ROLE;
GRANT USAGE ON STAGE hevy.raw.hevy_raw_stage TO ROLE HEVY_PIPELINE_ROLE;
GRANT USAGE ON FILE FORMAT hevy.raw.csv_ff TO ROLE HEVY_PIPELINE_ROLE;
GRANT USAGE ON INTEGRATION hevy_s3_int TO ROLE HEVY_PIPELINE_ROLE;

-- bronze: dbt needs to create/rebuild models here (Phase 5), plus read/write
-- the watermark control table directly (Airflow updates it in Phase 8).
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA hevy.bronze TO ROLE HEVY_PIPELINE_ROLE;
GRANT SELECT, INSERT, UPDATE ON TABLE hevy.bronze.pipeline_control TO ROLE HEVY_PIPELINE_ROLE;

-- gold: dbt needs to create/rebuild models here (Phase 6)
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA hevy.gold TO ROLE HEVY_PIPELINE_ROLE;

-- Attach the role to your user
GRANT ROLE HEVY_PIPELINE_ROLE TO USER TDAMODARAKA;

-- Sanity check
SHOW GRANTS TO ROLE HEVY_PIPELINE_ROLE;
