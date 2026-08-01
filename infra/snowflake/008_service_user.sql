-- Run as ACCOUNTADMIN in Snowsight.
-- Dedicated service user for automated pipeline runs (dbt/Airflow),
-- authenticating via RSA key-pair instead of password -- avoids the
-- MFA-on-personal-login problem entirely, since key-pair auth is a
-- separate mechanism that never triggers a Duo push. Mirrors the
-- hevy-pipeline-extractor IAM user pattern used for AWS in Phase 1.
--
-- TYPE = SERVICE marks this as a non-human/programmatic account: it
-- structurally cannot have a password set at all, so there's no risk of
-- ever falling back to password+MFA login by accident.

USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS HEVY_PIPELINE_SVC
  TYPE = SERVICE
  RSA_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1kmRKIsYQfVHGd78yoQU
VGkcq26dtHjym7L9xYzsTCPO6e0FSphTBDrvehmo+k6oHxnzXkQ4GLZ+2FjBREDh
O+Pf/nIo8lVCXkowOMoRn3OGgzQAxof3TPqPcDy7PoeuMWMomecHnUyINzfBbUtk
CGgjiKKMWjcfS+deydohN6ArqjpaG4DLmLAQMk2JDd4wyJpViotW+w4XqF07XkQH
DIIGSLNCJx38ha2Ey1qdTgdMwMRn4yCTyeJpGuHMcVuzhMS3zCQCyOtC3VYHKtoU
FlQrZKyyTB9wdJnrBMYo6lhHCl0xEZYt+aStchdtlGCzVuXvMkQKFOLEVBApgrnP
GwIDAQAB'
  DEFAULT_ROLE = HEVY_PIPELINE_ROLE
  DEFAULT_WAREHOUSE = hevy_wh
  COMMENT = 'Service account for the Hevy pipeline (dbt/Airflow). Key-pair auth only, no password, no MFA.';

-- If HEVY_PIPELINE_SVC already exists (e.g. the key was rotated after a
-- passphrase leak), CREATE ... IF NOT EXISTS above is a no-op -- use this
-- instead to push a new public key onto the existing user:
-- ALTER USER HEVY_PIPELINE_SVC SET RSA_PUBLIC_KEY = '<new key body>';

GRANT ROLE HEVY_PIPELINE_ROLE TO USER HEVY_PIPELINE_SVC;

-- Sanity check
DESCRIBE USER HEVY_PIPELINE_SVC;
