# Runbook: Hevy changed their UI and scraping broke

`extraction/scrape_export.py` automates hevy.com's actual login and export
pages using selectors captured via `playwright codegen`. If Hevy changes
their login flow, settings page, or export button, `scrape_export` will fail
— typically a `TimeoutError` on one of the `page.get_by_role(...)` /
`page.get_by_text(...)` calls, meaning the element it expected to click no
longer exists or moved.

This is expected, budgeted-for fragility (see the architecture doc's risks
section) — not a pipeline design problem.

## Immediate workaround: get this week's data in without fixing the scraper

1. Log into hevy.com yourself in a normal browser, and manually export your
   workout history (Settings → Export Data → Export Workout Data). This
   downloads the same CSV `scrape_export` would have.

2. Upload it to S3 yourself, from the repo root with the venv active:

   ```powershell
   .\venv\Scripts\python.exe extraction\upload_s3.py <path-to-downloaded-csv>
   ```

   This lands it at `s3://<bucket>/raw/hevy/dt=<today>/export.csv` — exactly
   where `upload_raw` would have put it.

3. In the Airflow UI (`localhost:8080`), open the `hevy_pipeline` DAG's
   Grid view for today's run. Click the `scrape_export` task instance, then
   the `upload_raw` task instance, and use **Mark state as → success** on
   each (there's no equivalent Airflow 3.x CLI command for this — it has to
   go through the UI or the REST API).

4. Manually trigger the rest of the run from `check_new_rows` onward — in
   the Grid view, click `check_new_rows` and choose **Run** (or clear it,
   which lets the scheduler pick it up). It'll read the CSV you already
   uploaded and continue normally: check the watermark, load, dbt, update
   the control table.

## Actually fixing the scraper

1. Run `playwright codegen https://hevy.com` locally (not headless) and
   manually click through login → Settings → Export Data → Export Workout
   Data. Codegen will print out the new selectors as you click.

2. Update the corresponding `page.get_by_role(...)` / `page.get_by_text(...)`
   calls in `extraction/scrape_export.py` to match.

3. Test locally first: `.\venv\Scripts\python.exe extraction\scrape_export.py --headed`
   (shows the browser window so you can watch it actually work), before
   relying on the headless in-container run again.

4. Once the whole DAG has run clean again through the UI, no further action
   needed — future weekly runs resume normally.
