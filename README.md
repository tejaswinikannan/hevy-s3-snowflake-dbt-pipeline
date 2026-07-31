# Hevy Pipeline

Personal data pipeline: pulls workout history from Hevy, lands it in S3, and loads it into Snowflake through a raw → bronze → gold medallion architecture using dbt, orchestrated weekly by a local Airflow instance.

See [`hevy-pipeline-architecture.md`](./hevy-pipeline-architecture.md) for the full architecture and design rationale.

**Status: under construction.** This README will be filled out with complete setup, operations, and troubleshooting docs once the pipeline is fully built.
