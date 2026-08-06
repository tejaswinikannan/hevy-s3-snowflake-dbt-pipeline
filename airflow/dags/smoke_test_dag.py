"""Throwaway DAG to prove the custom image works before any real pipeline
logic touches it. Safe to delete once Phase 8's real DAG is in place.
"""
from datetime import datetime

from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.operators.python import PythonOperator


def print_versions():
    from importlib.metadata import version

    import boto3
    import dbt.version

    print(f"boto3: {boto3.__version__}")
    print(f"playwright: {version('playwright')}")
    print(f"dbt-core: {dbt.version.installed}")


with DAG(
    dag_id="smoke_test",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["smoke-test"],
) as dag:
    check_python_imports = PythonOperator(
        task_id="check_python_imports",
        python_callable=print_versions,
    )

    check_dbt_cli = BashOperator(
        task_id="check_dbt_cli",
        bash_command="dbt --version",
    )
