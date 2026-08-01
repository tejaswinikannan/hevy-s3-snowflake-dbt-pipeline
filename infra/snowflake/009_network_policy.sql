-- Run as ACCOUNTADMIN in Snowsight.
-- Addresses Snowflake's Trust Center finding: "Ensure that all users are
-- covered by a network policy to only allow access from trusted IP
-- addresses." Scoped to HEVY_PIPELINE_SVC only (the automated/unattended
-- account, and thus the higher-value target) -- deliberately NOT applied to
-- the personal admin user, which relies on MFA and may log in from networks
-- other than home (phone, work, travel).
--
-- CAUTION: if your home ISP reassigns your public IP (common with dynamic
-- IPs), the pipeline will start failing to authenticate until this policy's
-- ALLOWED_IP_LIST is updated. If scrape/load tasks suddenly get connection
-- errors, check your current public IP (e.g. https://checkip.amazonaws.com)
-- against this list first.

-- Replace <your-home-ip> with your current public IP (check via
-- https://checkip.amazonaws.com) before running -- not committed here since
-- a public IP reveals your rough location/ISP and doesn't need to live in
-- git for the pipeline to work (it's only ever used at the moment this SQL
-- is run in Snowsight, never read by any application code).
CREATE NETWORK POLICY IF NOT EXISTS hevy_pipeline_svc_policy
  ALLOWED_IP_LIST = ('<your-home-ip>/32')
  COMMENT = 'Restricts HEVY_PIPELINE_SVC to the home network running Airflow/Docker Desktop.';

ALTER USER HEVY_PIPELINE_SVC SET NETWORK_POLICY = hevy_pipeline_svc_policy;

-- Sanity check
DESCRIBE NETWORK POLICY hevy_pipeline_svc_policy;
SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN USER HEVY_PIPELINE_SVC;

-- If your home IP ever changes, update the allow-list like this (doesn't
-- require dropping/recreating the policy):
-- ALTER NETWORK POLICY hevy_pipeline_svc_policy SET ALLOWED_IP_LIST = ('<new-ip>/32');
