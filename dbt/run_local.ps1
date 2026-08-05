# Loads .env from the repo root into environment variables, points dbt at
# this project's own profiles.yml (not the usual ~/.dbt/profiles.yml), and
# runs dbt with whatever arguments were passed through.
#
# Usage: .\dbt\run_local.ps1 build --select bronze_sets

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

Get-Content "$repoRoot\.env" | ForEach-Object {
    if ($_ -match '^([A-Za-z0-9_]+)=(.*)$') {
        Set-Item -Path "env:$($matches[1])" -Value $matches[2]
    }
}

$env:DBT_PROFILES_DIR = $PSScriptRoot

& "$repoRoot\venv\Scripts\dbt.exe" @args
