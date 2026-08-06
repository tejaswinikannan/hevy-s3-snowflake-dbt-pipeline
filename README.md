# Hevy Pipeline

A personal data pipeline: pulls workout history out of Hevy (browser-automated,
no official API), lands it in S3, and loads it into Snowflake through a
raw → bronze → gold medallion architecture using dbt, orchestrated weekly by
a local Airflow instance.

## Architecture

```
Hevy (web app)
   │  weekly: Playwright logs in, triggers export, downloads CSV
   ▼
extraction/  (Playwright + boto3, run inside the Airflow container)
   │  uploads raw CSV to S3, tagged with run date
   ▼
S3 raw landing zone   s3://<bucket>/raw/hevy/dt=YYYY-MM-DD/export.csv
   │  COPY INTO via a Snowflake external stage + storage integration
   ▼
Snowflake raw.hevy_export        (all columns STRING, full fidelity)
   │  dbt bronze: type-cast, dedupe, incremental merge past the watermark
   ▼
Snowflake bronze.bronze_sets     (one row per set, cleaned/typed)
   │  dbt gold: aggregations
   ▼
Snowflake gold.*                 (gold_session_volume, gold_prs, gold_weekly_totals)
```

Orchestrated by Airflow (`airflow/dags/hevy_pipeline_dag.py`), weekly on
`0 3 * * 0` (Sunday 3am):

1. `scrape_export` — Playwright logs into hevy.com, downloads the CSV
2. `upload_raw` — uploads it to S3
3. `check_new_rows` — compares the CSV's max `end_time` against the control
   table's watermark; if there's nothing new, every later task is **skipped**
   (not failed) and the run ends here
4. `load_bronze_raw` — `COPY INTO raw.hevy_export` from the S3 stage
5. `dbt_run_bronze` — incremental merge into `bronze.bronze_sets`
6. `dbt_run_gold` — full rebuild of the gold tables
7. `update_control_table` — advances the watermark and logs the row count

Every task from `load_bronze_raw` onward uses Airflow's default
`all_success` trigger rule — that's the entire mechanism that keeps a failed
dbt run from ever advancing the watermark. No custom error handling needed;
if step 5 or 6 fails, step 7 simply never runs.

## Repo layout

```
hevy-pipeline/
├── extraction/    Playwright scraper + S3 upload script
├── dbt/           dbt project: models/bronze, models/gold, tests, macros
├── airflow/       Dockerfile, docker-compose.yaml, DAG, load_raw.sql
└── infra/         versioned SQL (Snowflake) + a console runbook (AWS)
```

No Terraform (yet) — infra is either a written console runbook
(`infra/aws-runbook.md`) or plain versioned SQL run manually in Snowsight
(`infra/snowflake/001`–`009`, in order). This was a deliberate choice to
learn the AWS/Snowflake consoles directly before introducing IaC.

## Real-world corrections to the original plan

The architecture doc assumed a `completed_at` column and per-row IDs on the
Hevy export. The real export has neither:

- **Watermark field**: `end_time`, not `completed_at` — a per-workout
  timestamp shared by every set row in that workout. Format from the live
  extraction script: `"Jul 31, 2026, 6:52 PM"`.
- **No true row ID**: bronze's surrogate key is
  `md5(start_time || '|' || exercise_title || '|' || set_index)`. Known
  unresolved edge case: the same exercise appearing twice non-contiguously in
  one workout could collide on `set_index` — not observed in practice, not
  solved.
- **Strength vs. cardio**: sets mix strength (`weight_lbs`/`reps` populated)
  and cardio (`distance_miles`/`duration_seconds` populated); gold models
  branch on this rather than assuming both are always present.
- **Auth**: the original plan assumed a Snowflake password. The pipeline
  actually authenticates as a dedicated `TYPE = SERVICE` user
  (`HEVY_PIPELINE_SVC`) via RSA key-pair, because the personal login has MFA
  enabled (which would block unattended 3am automation).

## Setup from scratch

### 1. AWS

Follow [`infra/aws-runbook.md`](./infra/aws-runbook.md): S3 bucket, IAM user
for the extraction script, IAM role for Snowflake's storage integration.

### 2. Snowflake

Run `infra/snowflake/001` through `009` in order, manually, in Snowsight.
`003_storage_integration.sql` requires going back to the AWS console partway
through (`DESCRIBE INTEGRATION` → copy the generated ARN/external ID → paste
into the IAM role's trust policy) — see the comments in that file.

Generate the RSA key pair for the service user before running `008`:

```powershell
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_rsa_key.p8
openssl rsa -in snowflake_rsa_key.p8 -pubout -out snowflake_rsa_key.pub
```

You'll be prompted for a passphrase — that becomes
`SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` below. It encrypts the private key file at
rest; it's never sent to Snowflake. `008_service_user.sql` already has a real
`RSA_PUBLIC_KEY` value committed (public keys aren't secret) from this
build — replace it with your own `.pub` file's contents if rebuilding from
scratch, or use `ALTER USER ... SET RSA_PUBLIC_KEY` (commented in that file)
to rotate an existing user's key.

### 3. Python environment (local, for dbt and manual extraction runs)

```powershell
python -m venv venv
.\venv\Scripts\pip install -r extraction\requirements.txt -r dbt\requirements.txt
.\venv\Scripts\playwright install chromium
```

### 4. `.env`

Copy `.env.example` to `.env` and fill in every value. `.env` is gitignored —
never commit it.

### 5. Airflow

```powershell
cd airflow
docker compose up -d
```

Then open `http://localhost:8080` and log in with `airflow` / `airflow`
(Airflow's own default UI login — unrelated to any Snowflake or Hevy
credential). Go to **Admin → Connections → Add a new record** and create:

| Field | Value |
|---|---|
| Connection Id | `snowflake_default` |
| Connection Type | `Snowflake` |
| Login | value of `SNOWFLAKE_USER` |
| Password | value of `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` (**not** a real password — see below) |
| Schema | `raw` |
| Extra | `{"account": "<SNOWFLAKE_ACCOUNT>", "warehouse": "<SNOWFLAKE_WAREHOUSE>", "database": "<SNOWFLAKE_DATABASE>", "role": "<SNOWFLAKE_ROLE>", "private_key_file": "/opt/airflow/secrets/snowflake_rsa_key.p8"}` |

The Password field holds the private-key *passphrase*, not a password —
Snowflake auth here is key-pair based. The connector uses this connection's
`Password` field to decrypt the `.p8` file, then signs the actual connection
with what comes out.

Unpause `hevy_pipeline` in the UI (or `airflow dags unpause hevy_pipeline`)
once you're ready for it to run on schedule.

## How the watermark / incremental logic works

The Hevy export is a **full historical dump every time**, not just new data
— so incrementality happens at *load* time, not extraction time.
`bronze.pipeline_control` (schema `bronze`, not `raw` — it's pipeline
bookkeeping, not raw source data) holds one row per pipeline with
`last_watermark_ts`.

- `load_bronze_raw` (`COPY INTO`) loads the **entire** CSV into
  `raw.hevy_export`, unfiltered, every run. Snowflake's own load history
  makes re-running this against an already-loaded file a safe no-op.
- All "what's new" filtering happens in exactly one place:
  `dbt/models/bronze/bronze_sets.sql`'s `is_incremental()` block, which only
  processes rows where `end_time > last_watermark_ts`.
- `bronze_sets` merges (not appends) by its surrogate key, so re-running the
  same window twice can't create duplicates.
- The control table is only **written** by Airflow's `update_control_table`
  task, and only after `dbt_run_bronze` and `dbt_run_gold` both succeed. dbt
  itself never writes it — a local `dbt build` can't accidentally advance
  production state, and a failed dbt run structurally can't advance the
  watermark either (see the trigger-rule note above).
- `check_new_rows` short-circuits the whole load/dbt/watermark chain when the
  CSV has nothing past the current watermark — e.g. a week with no logged
  workouts. `load_bronze_raw` through `update_control_table` all show
  **skipped**, not failed.

## Running & monitoring

- **UI**: `http://localhost:8080`, `airflow`/`airflow`. The Graph view on
  `hevy_pipeline` is the fastest way to see where a run stands.
- **Manual trigger**: `docker exec airflow-airflow-apiserver-1 airflow dags trigger hevy_pipeline`
  (from the `airflow/` directory, container names come from `docker compose ps`).
- **Check a run's state**:
  `airflow dags state hevy_pipeline <run_id>` /
  `airflow tasks states-for-dag-run hevy_pipeline <run_id>`.
- **Verify the watermark actually moved**: query
  `select * from bronze.pipeline_control` in Snowsight — `last_watermark_ts`
  should be the max `end_time` from the most recent run that found new rows,
  `rows_loaded_last_run` its count.
- There's no alerting in v1 — check the UI manually. This is a deliberate
  trade-off for a low-stakes personal pipeline.

## Troubleshooting

**A task failed — where are the logs?**
`docker exec <apiserver-container> cat "/opt/airflow/logs/dag_id=hevy_pipeline/run_id=<run_id>/task_id=<task_id>/attempt=1.log"`,
or the UI's task log viewer.

**`scrape_export` times out waiting for the download.**
Hevy's export can take longer than a few seconds to generate server-side for
a large history. The timeout is already set to 120s in
`extraction/scrape_export.py`; if it's still not enough, raise it further.

**`dbt_run_bronze`/`dbt_run_gold` fail with a `KeyError` on a macro or
model file that clearly exists.**
Stale `dbt/target/partial_parse.msgpack` — its cache keys off the absolute
project path, which differs between local Windows runs
(`E:\...\dbt`) and the container (`/opt/airflow/dbt`). Both DAG tasks already
pass `--no-partial-parse` to sidestep this; if you're debugging manually
inside the container, do the same.

**Airflow can't connect to Snowflake at all.**
Check the home IP hasn't changed — `HEVY_PIPELINE_SVC` is restricted to a
single IP by a Snowflake network policy
(`infra/snowflake/009_network_policy.sql`). Update `ALLOWED_IP_LIST` there if
it has.

**Hevy changed their UI and scraping broke.**
See [`infra/hevy-scraping-broke-runbook.md`](./infra/hevy-scraping-broke-runbook.md).
