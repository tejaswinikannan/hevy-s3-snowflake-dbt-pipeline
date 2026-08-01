"""Entry point for the weekly extraction step: scrape Hevy's export, upload to S3.

Called directly by Airflow's scrape_export/upload_raw tasks (Phase 8).
"""
from scrape_export import scrape_export
from upload_s3 import upload_to_s3

if __name__ == "__main__":
    local_path = scrape_export(headless=True)
    print(f"Downloaded export to {local_path}")

    uri = upload_to_s3(local_path)
    print(f"Uploaded to {uri}")
