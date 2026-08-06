"""Weekly Hevy pipeline: scrape the export, land it in S3, load it into raw,
then run dbt bronze/gold -- advancing the watermark only after everything
succeeds.

check_new_rows short-circuits the whole load/dbt/watermark chain when the
CSV has nothing past the current watermark (e.g. a week with no logged
workouts). Every downstream task keeps Airflow's default all_success
trigger rule, which is what guarantees a failed dbt run can never advance
the watermark -- no bespoke error handling needed, just task dependencies.
See the build plan for the full architecture.
"""
import csv
from datetime import datetime
from pathlib import Path

from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.operators.python import PythonOperator, ShortCircuitOperator
from airflow.sdk import DAG

CSV_PATH = Path("/opt/airflow/extraction/downloads/workouts.csv")
END_TIME_FORMAT = "%b %d, %Y, %I:%M %p"  # e.g. "Jul 31, 2026, 6:52 PM"
SNOWFLAKE_CONN_ID = "snowflake_default"
DBT_RUN = "cd /opt/airflow/dbt && DBT_PROFILES_DIR=/opt/airflow/dbt dbt --no-partial-parse build --select {selector}"


def check_new_rows(ti, **context):
    hook = SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID)
    current_watermark = hook.get_first(
        "select last_watermark_ts from bronze.pipeline_control where pipeline_name = 'hevy'"
    )[0]

    max_end_time = None
    new_row_count = 0
    with CSV_PATH.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            end_time = datetime.strptime(row["end_time"], END_TIME_FORMAT)
            if max_end_time is None or end_time > max_end_time:
                max_end_time = end_time
            if end_time > current_watermark:
                new_row_count += 1

    ti.xcom_push(key="new_watermark", value=max_end_time.isoformat())
    ti.xcom_push(key="new_row_count", value=new_row_count)

    return max_end_time > current_watermark


def update_control_table(ti, **context):
    new_watermark = datetime.fromisoformat(
        ti.xcom_pull(task_ids="check_new_rows", key="new_watermark")
    )
    new_row_count = ti.xcom_pull(task_ids="check_new_rows", key="new_row_count")

    hook = SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID)
    hook.run(
        """
        update bronze.pipeline_control
        set last_watermark_ts = %(watermark)s,
            last_run_ts = current_timestamp(),
            rows_loaded_last_run = %(row_count)s
        where pipeline_name = 'hevy'
        """,
        parameters={"watermark": new_watermark, "row_count": new_row_count},
    )


with DAG(
    dag_id="hevy_pipeline",
    start_date=datetime(2026, 1, 1),
    schedule="0 3 * * 0",
    catchup=False,
    template_searchpath=[str(Path(__file__).parent)],
    tags=["hevy"],
) as dag:
    scrape_export = BashOperator(
        task_id="scrape_export",
        bash_command="python /opt/airflow/extraction/scrape_export.py",
    )

    upload_raw = BashOperator(
        task_id="upload_raw",
        bash_command=f"python /opt/airflow/extraction/upload_s3.py {CSV_PATH}",
    )

    check_new_rows_task = ShortCircuitOperator(
        task_id="check_new_rows",
        python_callable=check_new_rows,
    )

    load_bronze_raw = SQLExecuteQueryOperator(
        task_id="load_bronze_raw",
        conn_id=SNOWFLAKE_CONN_ID,
        sql="sql/load_raw.sql",
    )

    dbt_run_bronze = BashOperator(
        task_id="dbt_run_bronze",
        bash_command=DBT_RUN.format(selector="bronze_sets"),
    )

    dbt_run_gold = BashOperator(
        task_id="dbt_run_gold",
        bash_command=DBT_RUN.format(selector="gold"),
    )

    update_control_table_task = PythonOperator(
        task_id="update_control_table",
        python_callable=update_control_table,
    )

    (
        scrape_export
        >> upload_raw
        >> check_new_rows_task
        >> load_bronze_raw
        >> dbt_run_bronze
        >> dbt_run_gold
        >> update_control_table_task
    )
