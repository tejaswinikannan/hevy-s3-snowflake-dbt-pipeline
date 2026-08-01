"""Uploads a local Hevy export CSV to the S3 raw landing zone."""
import argparse
import os
from datetime import date
from pathlib import Path

import boto3
from dotenv import load_dotenv

load_dotenv()


def upload_to_s3(local_path: Path, run_date: date | None = None) -> str:
    run_date = run_date or date.today()
    key = f"raw/hevy/dt={run_date.isoformat()}/export.csv"

    s3 = boto3.client(
        "s3",
        aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
        region_name=os.environ["AWS_REGION"],
    )
    s3.upload_file(str(local_path), os.environ["S3_BUCKET"], key)

    return f"s3://{os.environ['S3_BUCKET']}/{key}"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path, help="Local CSV file to upload")
    args = parser.parse_args()

    uri = upload_to_s3(args.path)
    print(f"Uploaded to {uri}")
