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
- **Trust policy**: currently a placeholder (trusts own account root, external ID `0000000000`). **Finalized in Phase 2** once Snowflake's storage integration provides its real `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID` — those values replace the placeholders here.
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
