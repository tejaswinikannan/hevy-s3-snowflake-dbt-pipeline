"""Logs into hevy.com and downloads the workout history CSV export.

Selectors below were captured via `playwright codegen https://hevy.com`
(see the build plan) -- if Hevy changes their UI, re-run codegen and
update the locators here.
"""
import argparse
import os
from pathlib import Path

from dotenv import load_dotenv
from playwright.sync_api import sync_playwright

load_dotenv()

DOWNLOAD_DIR = Path(__file__).parent / "downloads"


def scrape_export(headless: bool = True) -> Path:
    DOWNLOAD_DIR.mkdir(exist_ok=True)

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=headless)
        context = browser.new_context()
        page = context.new_page()

        page.goto("https://hevy.com/login?postLoginPath=%2F")
        page.get_by_role("textbox").first.click()
        page.get_by_role("textbox").first.fill(os.environ["HEVY_EMAIL"])
        page.get_by_role("textbox").first.press("Tab")
        page.locator('input[type="password"]').fill(os.environ["HEVY_PASSWORD"])
        page.get_by_role("button", name="Login", exact=True).click()

        page.get_by_role("link", name="Settings").click()
        page.get_by_text("Export Data").click()

        with page.expect_download() as download_info:
            page.get_by_role("button", name="Export Workout Data").click()

        dest = DOWNLOAD_DIR / "workouts.csv"
        download_info.value.save_as(dest)

        context.close()
        browser.close()

    return dest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--headed", action="store_true", help="Show the browser window (for debugging)")
    args = parser.parse_args()

    path = scrape_export(headless=not args.headed)
    print(f"Downloaded export to {path}")
