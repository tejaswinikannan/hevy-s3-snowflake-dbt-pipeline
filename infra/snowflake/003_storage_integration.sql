-- Run as ACCOUNTADMIN in Snowsight.
-- Part A: create the storage integration pointing at the S3 bucket and the
-- placeholder-trust IAM role from Phase 1 (infra/aws-runbook.md section 3).
--
-- This is a two-way handshake:
--   1. This statement tells Snowflake "here's the AWS role you should assume."
--   2. DESCRIBE INTEGRATION (part B, below) then reveals Snowflake's own AWS
--      identity (STORAGE_AWS_IAM_USER_ARN) and a secret STORAGE_AWS_EXTERNAL_ID.
--   3. Those two values get pasted into the IAM role's trust policy back in
--      AWS (part C) -- only then can Snowflake actually assume the role.

CREATE STORAGE INTEGRATION IF NOT EXISTS hevy_s3_int
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::670934648000:role/snowflake-hevy-s3-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://hevy-pipeline-dteja93/raw/hevy/');

-- Part B: reveal Snowflake's identity so we can finish the AWS side.
DESCRIBE INTEGRATION hevy_s3_int;
