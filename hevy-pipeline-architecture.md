# Hevy Workout Data Pipeline — Architecture & Cost Estimate

Based on your answers: Hevy export is manual (no API), extraction will be automated via browser scraping, Airflow runs on your own machine, everything else lives on AWS/Snowflake, versioning is Git + dbt, you're starting from zero on both AWS and Snowflake, and the pipeline runs **weekly** (not nightly) to keep Snowflake cost minimal.

## 1. Architecture

```
Hevy (web app)
   │  nightly: Playwright script logs in, triggers export, downloads CSV
   ▼
Local machine (Airflow scheduler + workers, Docker Compose)
   │  uploads raw CSV to S3, tagged with run date
   ▼
S3 — raw/landing zone  (s3://.../raw/hevy/dt=YYYY-MM-DD/export.csv)
   │  COPY INTO via Snowflake external stage
   ▼
Snowflake — RAW / BRONZE
   │  dbt: type casting, dedup by workout+exercise+set id, only rows newer
   │  than the control table's watermark get inserted
   ▼
Snowflake — BRONZE (cleaned, one row per set)
   │  dbt: joins, aggregations (volume per session, PRs, weekly totals, etc.)
   ▼
Snowflake — GOLD (analytics-ready)  ──► consumed by analytics team
```

Orchestration (Airflow, local machine) runs **weekly** (e.g. Sunday 3am — `0 3 * * 0`):
1. `scrape_export` — Playwright logs into hevy.com, downloads CSV
2. `upload_raw` — pushes file to S3 landing zone
3. `load_bronze_raw` — COPY INTO Snowflake raw table from S3 stage
4. `dbt_run_bronze` — clean/dedupe, insert only rows past the watermark
5. `dbt_run_gold` — rebuild aggregates
6. `update_control_table` — advance the watermark, log row counts

If a run finds no rows past the watermark (nothing new since last week), steps 3–6 still no-op rather than waking the Snowflake warehouse for nothing.

**Trade-off to be aware of**: the analytics team's gold tables now refresh weekly instead of nightly. Given you only work out 3–4x/week and export manually, weekly is a natural fit — but worth confirming that latency is acceptable for whoever consumes the gold layer.

## 2. Incremental control table

Since the export is a full historical dump each time (not just new data), incrementality happens at *load* time, not extraction time:

```sql
create table bronze.pipeline_control (
    pipeline_name       string,
    last_watermark_ts   timestamp_ntz,  -- max workout completed_at already loaded
    last_run_ts         timestamp_ntz,
    rows_loaded_last_run number
);
```

Each run: read the watermark, filter the raw export to rows with `completed_at > last_watermark_ts`, load only those, then update the watermark to the new max.

## 3. Repo structure (modular, Git-versioned)

```
hevy-pipeline/
├── extraction/        # Playwright scraper + S3 upload script
├── dbt/               # dbt project: models/bronze, models/gold, tests, macros
├── airflow/            # DAG definitions + docker-compose.yml
└── infra/             # Terraform: S3 bucket, IAM user/policy, Snowflake objects
```

Git versions all code (extraction script, Airflow DAGs, infra). dbt is where modularity and "version control for transformations" really shows up: each bronze/gold table is its own model file, dbt tracks dependencies between them (lineage graph), and model changes are just Git commits to the dbt project. Snowflake's Time Travel also gives native point-in-time recovery on the underlying tables.

## 4. Cost estimate

**Given Airflow and the scraper run on your own machine, AWS is only doing storage — no EC2/Fargate/MWAA needed.**

| AWS item | Estimate |
|---|---|
| S3 storage (<1MB/day, ~365MB/yr) | ~$0.01/mo |
| S3 requests (daily PUT/GET) | ~$0.01/mo |
| IAM, S3→Snowflake same-region transfer | Free |
| Secrets Manager (optional, if not using local .env) | ~$0.40/mo |
| **AWS total** | **< $1–2/month** |

| Snowflake item | Estimate |
|---|---|
| XS warehouse, ~10 min active/run | ~0.17 credits/run |
| Weekly runs (~4/mo) | ~0.7 credits/mo → **~$1.50–2/mo** (Standard edition, ~$2–3/credit) |
| Storage (<1MB) | Negligible |
| **Snowflake total** | **~$1.50–2/month** |

(For reference, if this ran nightly instead of weekly, it'd be ~5 credits/mo → ~$10–15/mo. Weekly cuts that by roughly 7x.)

Snowflake billing is separate from AWS unless set up via AWS Marketplace. New Snowflake accounts also get a $400 trial credit, so this is effectively free for the first month or two regardless.

**Realistic total: ~$2–4/month** (AWS storage pennies + Snowflake ~$1.50–2).

## 5. Risks / things to be aware of

- **Scraping fragility**: automating hevy.com's UI will break if they change their login flow or export page. Budget for occasional maintenance.
- **ToS**: scripted login to automate an export isn't an officially supported integration — low risk for personal use, but worth knowing.
- **Credential storage**: your Hevy login needs to live somewhere the scraper can read it (local `.env` or OS keychain on your machine, since Airflow runs there — no need for AWS Secrets Manager unless you want centralized secret storage anyway).
- **Single point of failure**: since Airflow lives on your machine, the nightly run only happens if that machine is on and online at the scheduled time.

## 6. Still need from you

1. A sample export file (CSV/Excel) — actual column names so the bronze schema and watermark field can be defined precisely.
2. How you want the scraper to read your Hevy login (env var, local keychain, something else).
3. Confirm assumptions: AWS region (defaulting to `us-east-1`), Snowflake edition (defaulting to Standard — cheapest, sufficient here), Terraform for infra-as-code, dbt Core (not dbt Cloud).
4. Any preference on failure alerting (email/Slack on a failed run) — optional, not required to start.
