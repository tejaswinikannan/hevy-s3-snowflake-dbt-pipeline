# Hevy Workout Data Pipeline — Architecture & Cost Estimate

Based on your answers: Hevy export is manual (no API), extraction will be automated via browser scraping, Airflow runs on your own machine, everything else lives on AWS/Snowflake, versioning is Git + dbt, you're starting from zero on both AWS and Snowflake, and the pipeline runs **weekly** (not nightly) to keep Snowflake cost minimal.

> **Note**: this is the original planning doc, written before anything was
> built. A few assumptions here turned out wrong once real data and real
> infra showed up — corrected inline below, marked with ⚠. For the current,
> as-built state (setup instructions, real watermark logic, monitoring,
> troubleshooting), see the [README](./README.md).

## 1. Architecture

```
Hevy (web app)
   │  weekly: Playwright script logs in, triggers export, downloads CSV  ⚠ was "nightly" here, weekly everywhere else
   ▼
Local machine (Airflow, Docker Compose, LocalExecutor)  ⚠ no separate worker/broker -- see below
   │  uploads raw CSV to S3, tagged with run date
   ▼
S3 — raw/landing zone  (s3://.../raw/hevy/dt=YYYY-MM-DD/export.csv)
   │  COPY INTO via Snowflake external stage
   ▼
Snowflake — RAW (raw.hevy_export)
   │  dbt: type casting, dedup by a surrogate key (no true row ID exists --
   │  see corrected schema notes below), only rows newer than the control
   │  table's watermark get inserted
   ▼
Snowflake — BRONZE (cleaned, one row per set)
   │  dbt: joins, aggregations (volume per session, PRs, weekly totals, etc.)
   ▼
Snowflake — GOLD (analytics-ready)  ──► queried directly in Snowsight (personal project, no separate analytics team)
```

⚠ **LocalExecutor, not Celery**: this pipeline runs one weekly DAG on one
machine, so a distributed broker/worker setup (Redis + Celery workers +
Flower) would be pure overhead. Tasks run as subprocesses of the scheduler
itself.

Orchestration (Airflow, local machine) runs **weekly** (Sunday 3am — `0 3 * * 0`):
1. `scrape_export` — Playwright logs into hevy.com, downloads CSV
2. `upload_raw` — pushes file to S3 landing zone
3. `check_new_rows` — ⚠ added during the build: compares the CSV's max
   watermark field against the control table before doing anything else
4. `load_bronze_raw` — COPY INTO Snowflake raw table from S3 stage
5. `dbt_run_bronze` — clean/dedupe, insert only rows past the watermark
6. `dbt_run_gold` — rebuild aggregates
7. `update_control_table` — advance the watermark, log row counts

If a run finds no rows past the watermark (nothing new since last week),
steps 4–7 are skipped. ⚠ Step 3 does still briefly resume the Snowflake
warehouse to read the current watermark even when nothing's new (pennies,
not literally free) — an accepted trade-off, not the zero-cost no-op this
originally implied.

**Trade-off to be aware of**: gold tables refresh weekly instead of nightly.
Since this is a personal pipeline queried directly by you, and you only
work out 3–4x/week, weekly latency is a natural fit — there's no separate
downstream consumer to check in with.

## 2. Incremental control table

Since the export is a full historical dump each time (not just new data), incrementality happens at *load* time, not extraction time:

```sql
create table bronze.pipeline_control (
    pipeline_name       string,
    last_watermark_ts   timestamp_ntz,  -- max end_time already loaded
    last_run_ts         timestamp_ntz,
    rows_loaded_last_run number
);
```

Each run: read the watermark, filter to rows with `end_time > last_watermark_ts`, load only those, then update the watermark to the new max.

⚠ **Corrected from the original plan**: the real Hevy export has no
`completed_at` column at all (that was a hypothetical field name, not
verified against real data at the time this was written). The real
watermark field is `end_time` — a per-workout timestamp shared by every set
row in that workout. The real export also has no true row-level ID
(`workout_id`/`set_id`); the "dedup by workout+exercise+set id" mentioned
above is actually a surrogate key over `(start_time, exercise_title,
set_index)`, since none of those exist as real columns either. See the
[README](./README.md#real-world-corrections-to-the-original-plan) for the
full list of corrections found once a real export was in hand.

## 3. Repo structure (modular, Git-versioned)

```
hevy-pipeline/
├── extraction/        # Playwright scraper + S3 upload script
├── dbt/               # dbt project: models/bronze, models/gold, tests, macros
├── airflow/           # Dockerfile, docker-compose.yaml, DAG definitions
└── infra/             # versioned SQL (Snowflake) + a written console runbook (AWS)
```

⚠ **No Terraform** — a deliberate choice, not an oversight. You're starting
from zero on both AWS and Snowflake consoles and wanted to learn them
hands-on first; Terraform is an explicit later upgrade once that's
comfortable. `infra/snowflake/001`–`009` are plain SQL scripts run manually
in Snowsight, and `infra/aws-runbook.md` documents the AWS console steps.

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

- **Scraping fragility**: automating hevy.com's UI will break if they change their login flow or export page. Budget for occasional maintenance. ⚠ Already partially materialized once during the build, though not from a UI change: Playwright's default 30s timeout waiting for the export download turned out too tight for Hevy to generate a full historical export server-side. See [`infra/hevy-scraping-broke-runbook.md`](./infra/hevy-scraping-broke-runbook.md) for the manual-workaround-plus-fix playbook if the selectors themselves ever break.
- **ToS**: scripted login to automate an export isn't an officially supported integration — low risk for personal use, but worth knowing.
- **Credential storage**: your Hevy login needs to live somewhere the scraper can read it (local `.env` or OS keychain on your machine, since Airflow runs there — no need for AWS Secrets Manager unless you want centralized secret storage anyway). ⚠ Snowflake credential storage turned out more involved than a simple password: the pipeline authenticates as a dedicated `TYPE = SERVICE` user via RSA key-pair (personal login has MFA, which would block unattended runs), so there's also a private key file and a passphrase to manage — see the README's setup section.
- **Single point of failure**: since Airflow lives on your machine, the weekly run only happens if that machine is on and online at the scheduled time.
