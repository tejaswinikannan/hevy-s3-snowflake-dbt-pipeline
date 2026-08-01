-- Run as ACCOUNTADMIN in Snowsight.
-- File format matching Hevy's CSV export (see workouts.csv sample: quoted
-- fields, header row, UTF-8 with emoji in titles).

USE DATABASE hevy;
USE SCHEMA raw;

CREATE FILE FORMAT IF NOT EXISTS csv_ff
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  ENCODING = 'UTF8';

CREATE STAGE IF NOT EXISTS hevy_raw_stage
  URL = 's3://hevy-pipeline-dteja93/raw/hevy/'
  STORAGE_INTEGRATION = hevy_s3_int
  FILE_FORMAT = csv_ff;

-- The real test: if the storage integration + trust policy handshake worked,
-- this lists the test.txt file uploaded back in Phase 1's verification step.
LIST @hevy_raw_stage;
