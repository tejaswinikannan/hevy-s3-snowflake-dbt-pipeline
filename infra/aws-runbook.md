# AWS Console Runbook — Hevy Pipeline

Manual setup steps for the AWS resources this pipeline depends on. No Terraform yet (deliberate — see architecture doc); these are the exact console steps to recreate the setup if needed.

## 1. S3 bucket (raw landing zone)

- **Bucket name**: `hevy-pipeline-dteja93`
- **Region**: `us-east-1`
- **Object Ownership**: ACLs disabled (default)
- **Block Public Access**: all four boxes checked (fully blocked)
- **Versioning**: disabled
- **Default encryption**: SSE-S3 (Amazon S3 managed keys)

Raw Hevy exports land at `s3://hevy-pipeline-dteja93/raw/hevy/dt=YYYY-MM-DD/export.csv`.

## 2. IAM user for the extraction script

- **User**: `hevy-pipeline-extractor` — programmatic access only (no console login).
- **Policy**: `hevy-pipeline-extractor-policy` (customer-managed, attached directly), scoped to `s3:ListBucket` (conditioned to the `raw/hevy/*` prefix), `s3:PutObject`, `s3:GetObject` on `s3://hevy-pipeline-dteja93/raw/hevy/*`.
- **Access key**: created via Security credentials → Create access key (use case: Third-party service). Key ID/secret stored in local `.env`, never committed.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucketRawPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::hevy-pipeline-dteja93",
      "Condition": { "StringLike": { "s3:prefix": "raw/hevy/*" } }
    },
    {
      "Sid": "ReadWriteRawPrefix",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::hevy-pipeline-dteja93/raw/hevy/*"
    }
  ]
}
```

**Verified 2026-07-31**: using the extractor user's access key, `aws s3 cp` to `raw/hevy/dt=.../test.txt` succeeded; `aws s3 ls` on the bucket root and `aws s3 cp` to a different prefix were both denied with `AccessDenied` — confirms the policy's scoping actually holds, not just that it's attached.

## 3. IAM role for Snowflake (assumed via storage integration)

- **Role**: `snowflake-hevy-s3-role`
- **ARN**: `arn:aws:iam::<your-account-id>:role/snowflake-hevy-s3-role`
- **Trust policy**: finalized in Phase 2 — trusts Snowflake's actual per-integration IAM user (`STORAGE_AWS_IAM_USER_ARN` from `DESCRIBE INTEGRATION hevy_s3_int`), conditioned on Snowflake's `STORAGE_AWS_EXTERNAL_ID`. The real values aren't recorded here (not committed) — see `infra/snowflake/003_storage_integration.sql` for how to regenerate them if this needs rebuilding; re-run `DESCRIBE INTEGRATION hevy_s3_int;` in Snowsight to see the current values.
- **Verified 2026-07-31**: `LIST @hevy_raw_stage;` in Snowsight successfully listed the test file uploaded during Phase 1 — confirms the full cross-account handshake (role, trust policy, storage integration, stage) works end-to-end.
- **Inline policy**: `hevy-s3-read-policy` — read-only (`s3:ListBucket` conditioned to `raw/hevy/*`, `s3:GetObject`, `s3:GetObjectVersion`) on the same bucket/prefix as the extractor user.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucketRawPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::hevy-pipeline-dteja93",
      "Condition": { "StringLike": { "s3:prefix": "raw/hevy/*" } }
    },
    {
      "Sid": "ReadRawPrefix",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:GetObjectVersion"],
      "Resource": "arn:aws:s3:::hevy-pipeline-dteja93/raw/hevy/*"
    }
  ]
}
```
