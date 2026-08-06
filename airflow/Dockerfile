# Custom Airflow image: base + Playwright/Chromium + dbt + Snowflake/AWS
# providers, all in one image. Chosen over DockerOperator-per-task (avoids
# mounting the Docker socket into the container, fiddly on Windows Docker
# Desktop) and over CeleryExecutor (Redis/worker/flower is pure overhead
# for one weekly DAG on one machine) -- see the build plan for the full
# reasoning.

FROM apache/airflow:3.3.0-python3.11

USER airflow
RUN pip install --no-cache-dir \
    playwright==1.61.0 \
    dbt-core \
    dbt-snowflake \
    boto3 \
    python-dotenv \
    apache-airflow-providers-standard \
    apache-airflow-providers-snowflake \
    apache-airflow-providers-amazon

# Playwright's system-level browser dependencies need root (apt-get);
# the actual browser binary download runs as airflow so it lands in that
# user's cache dir, where tasks (running as airflow) will actually find it.
USER root
RUN HOME=/home/airflow playwright install-deps chromium

USER airflow
RUN playwright install chromium
